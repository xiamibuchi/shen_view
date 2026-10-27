/// A user-visible directory or archive in the bounded navigation path.
class ViewerLocation {
  const ViewerLocation({
    required this.path,
    required this.name,
    this.isArchive = false,
  });

  final String path;
  final String name;
  final bool isArchive;
}
