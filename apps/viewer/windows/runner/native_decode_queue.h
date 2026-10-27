#ifndef RUNNER_NATIVE_DECODE_QUEUE_H_
#define RUNNER_NATIVE_DECODE_QUEUE_H_

#include <algorithm>
#include <atomic>
#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

// Mirrors DecodePriority: foreground=0, visible=1, all others are auxiliary.
// The outer Dart scheduler still owns total admission and memory reservations.
template <typename Payload>
class NativeDecodeQueue {
 public:
  struct Task {
    int64_t id = 0;
    int priority = 0;
    double distance = 0;
    uint64_t sequence = 0;
    std::atomic<bool> cancelled{false};
    Payload payload;
  };
  using Job = std::shared_ptr<Task>;
  using Callback = std::function<void(const Job&)>;

  NativeDecodeQueue(Callback execute, Callback complete,
                    std::function<void()> initialize = {},
                    std::function<void()> finalize = {})
      : execute_(std::move(execute)), complete_(std::move(complete)),
        initialize_(std::move(initialize)), finalize_(std::move(finalize)) {
    workers_.emplace_back([this] { Work(true); });
    workers_.emplace_back([this] { Work(false); });
  }
  ~NativeDecodeQueue() { Stop(); }
  NativeDecodeQueue(const NativeDecodeQueue&) = delete;
  NativeDecodeQueue& operator=(const NativeDecodeQueue&) = delete;

  void Enqueue(const Job& task) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (stopping_) return;
      task->priority = std::clamp(task->priority, 0, 7);
      task->distance = Distance(task->distance);
      task->sequence = sequence_++;
      tasks_[task->id] = task;
      pending_.push_back(task);
    }
    condition_.notify_all();
  }

  void UpdatePriority(int64_t id, int priority, double distance) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      const auto item = tasks_.find(id);
      if (item == tasks_.end()) return;
      item->second->priority = std::clamp(priority, 0, 7);
      item->second->distance = Distance(distance);
    }
    condition_.notify_all();
  }

  void Cancel(int64_t id) {
    Job removed;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      const auto item = tasks_.find(id);
      if (item == tasks_.end()) return;
      item->second->cancelled.store(true);
      const auto queued = std::find(pending_.begin(), pending_.end(), item->second);
      if (queued != pending_.end()) {
        removed = *queued;
        pending_.erase(queued);
        tasks_.erase(item);
      }
    }
    // Queued cancellation completes independently of a blocked codec. Running
    // cancellation completes only after execute_ has really released its work.
    if (removed) complete_(removed);
  }

  void Stop() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (stopping_) return;
      stopping_ = true;
      for (const auto& item : tasks_) item.second->cancelled.store(true);
      pending_.clear();
    }
    condition_.notify_all();
    for (auto& worker : workers_) {
      if (worker.joinable()) worker.join();
    }
    std::lock_guard<std::mutex> lock(mutex_);
    tasks_.clear();
  }

  // Retain the cancellation flag until the platform thread delivers the reply.
  void Acknowledge(int64_t id) {
    std::lock_guard<std::mutex> lock(mutex_);
    tasks_.erase(id);
  }

 private:
  static double Distance(double value) {
    return std::isfinite(value) ? std::max(0.0, value) : 1.0e300;
  }

  auto Next(bool foregroundOnly) {
    auto best = pending_.end();
    for (auto item = pending_.begin(); item != pending_.end(); ++item) {
      if (foregroundOnly && (*item)->priority > 1) continue;
      if (best == pending_.end() || (*item)->priority < (*best)->priority ||
          ((*item)->priority == (*best)->priority &&
           ((*item)->distance < (*best)->distance ||
            ((*item)->distance == (*best)->distance &&
             (*item)->sequence < (*best)->sequence)))) best = item;
    }
    return best;
  }

  void Work(bool foregroundOnly) {
    if (initialize_) initialize_();
    while (true) {
      Job task;
      {
        std::unique_lock<std::mutex> lock(mutex_);
        condition_.wait(lock, [this, foregroundOnly] {
          return stopping_ || Next(foregroundOnly) != pending_.end();
        });
        if (stopping_) break;
        const auto next = Next(foregroundOnly);
        task = *next;
        pending_.erase(next);
      }
      if (!task->cancelled.load()) execute_(task);
      {
        std::lock_guard<std::mutex> lock(mutex_);
        if (stopping_) break;
      }
      complete_(task);
    }
    if (finalize_) finalize_();
  }

  Callback execute_;
  Callback complete_;
  std::function<void()> initialize_;
  std::function<void()> finalize_;
  std::mutex mutex_;
  std::condition_variable condition_;
  std::deque<Job> pending_;
  std::map<int64_t, Job> tasks_;
  std::vector<std::thread> workers_;
  uint64_t sequence_ = 0;
  bool stopping_ = false;
};

#endif
