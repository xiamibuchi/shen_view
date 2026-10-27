/// Recursive modes keep folder entries ([recursiveFolders]) or merge descendant
/// images into the current strip ([recursiveFlat]).
enum FolderBrowseMode {
  currentFolder,
  recursiveFolders,
  recursiveFlat;

  bool get isRecursive => this != FolderBrowseMode.currentFolder;

  bool get isFlat => this == FolderBrowseMode.recursiveFlat;
}
