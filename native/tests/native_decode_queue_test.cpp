#include "../../apps/viewer/windows/runner/native_decode_queue.h"

#include <chrono>
#include <future>
#include <iostream>
#include <stdexcept>
#include <string>

using namespace std::chrono_literals;

struct Payload {
  std::function<void()> work = [] {};
  std::promise<void> started;
  std::promise<void> completed;
  std::atomic<int> completions{0};
};
using Queue = NativeDecodeQueue<Payload>;

void Require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

Queue::Job Job(int id, int priority) {
  auto task = std::make_shared<Queue::Task>();
  task->id = id;
  task->priority = priority;
  return task;
}

void Wait(std::future<void> future) {
  Require(future.wait_for(3s) == std::future_status::ready, "timed out");
  future.get();
}

void Run() {
  std::promise<void> releaseAux;
  auto auxGate = releaseAux.get_future().share();
  std::promise<void> releaseFront;
  auto frontGate = releaseFront.get_future().share();
  std::promise<void> releaseSecond;
  auto secondGate = releaseSecond.get_future().share();
  auto auxiliary = Job(1, 6);
  auto main = Job(2, 0);
  auto queued = Job(3, 6);
  auto promoted = Job(4, 7);
  auto other = Job(5, 5);
  auxiliary->payload.work = [auxGate] { auxGate.wait(); };
  main->payload.work = [frontGate] { frontGate.wait(); };
  promoted->payload.work = [secondGate] { secondGate.wait(); };
  Queue queue(
      [](const Queue::Job& task) {
        task->payload.started.set_value();
        task->payload.work();
      },
      [](const Queue::Job& task) {
        if (++task->payload.completions == 1) task->payload.completed.set_value();
      });
  try {
    queue.Enqueue(auxiliary);
    Wait(auxiliary->payload.started.get_future());
    queue.Enqueue(main);
    Wait(main->payload.started.get_future());
    // A blocked auxiliary must not occupy the reserved main lane.
    queue.Enqueue(queued);
    auto queuedStart = queued->payload.started.get_future();
    queue.Cancel(queued->id);
    Wait(queued->payload.completed.get_future());
    Require(queuedStart.wait_for(0ms) != std::future_status::ready, "cancelled task ran");
    queue.Cancel(queued->id);
    Require(queued->payload.completions.load() == 1, "queued callback repeated");

    queue.Enqueue(other);
    queue.Enqueue(promoted);
    queue.UpdatePriority(promoted->id, 0, 0);
    releaseFront.set_value();
    Wait(main->payload.completed.get_future());
    Wait(promoted->payload.started.get_future());
    // Promotion wakes the reserved lane without waiting for the auxiliary.
    queue.Cancel(promoted->id);
    auto promotedDone = promoted->payload.completed.get_future();
    Require(promotedDone.wait_for(20ms) != std::future_status::ready,
            "running task completed before releasing actual work");
    releaseSecond.set_value();
    Wait(std::move(promotedDone));
    Require(promoted->cancelled.load(), "running cancellation was lost");
    queue.Cancel(other->id);
    Wait(other->payload.completed.get_future());
    releaseAux.set_value();
    Wait(auxiliary->payload.completed.get_future());
    // Finished but not delivered results must still accept cancellation.
    queue.Cancel(auxiliary->id);
    Require(auxiliary->cancelled.load(), "late cancellation was lost");
    queue.Acknowledge(auxiliary->id);
    queue.Stop();
  } catch (...) {
    // Release all fake codecs before queue's joining destructor runs.
    try { releaseFront.set_value(); } catch (...) {}
    try { releaseSecond.set_value(); } catch (...) {}
    try { releaseAux.set_value(); } catch (...) {}
    queue.Stop();
    throw;
  }
}

void Ordering() {
  std::promise<void> release;
  auto gate = release.get_future().share();
  std::vector<int64_t> order;
  auto blocker = Job(10, 6);
  blocker->payload.work = [gate] { gate.wait(); };
  Queue queue(
      [&order](const Queue::Job& task) {
        order.push_back(task->id);
        task->payload.started.set_value();
        task->payload.work();
      },
      [](const Queue::Job& task) { task->payload.completed.set_value(); });
  try {
    queue.Enqueue(blocker);
    Wait(blocker->payload.started.get_future());
    auto far = Job(11, 5); far->distance = 20;
    auto near = Job(12, 5); near->distance = 1;
    auto tied = Job(13, 5); tied->distance = 1;
    auto low = Job(14, 7); low->distance = 0;
    for (const auto& task : {far, near, tied, low}) queue.Enqueue(task);
    release.set_value();
    for (const auto& task : {blocker, far, near, tied, low}) {
      Wait(task->payload.completed.get_future());
    }
    Require(order == std::vector<int64_t>({10, 12, 13, 11, 14}),
            "priority, distance or stable FIFO order was lost");
    queue.Stop();
  } catch (...) {
    try { release.set_value(); } catch (...) {}
    queue.Stop();
    throw;
  }
}

int main() {
  try {
    for (int iteration = 0; iteration < 30; ++iteration) { Run(); Ordering(); }
    std::cout << "PASS: main lane, priority/distance/FIFO, promotion, queued/running/late cancellation (30 iterations)\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
