enum SortOrder {
  nameAscending,
  nameDescending,
  modifiedNewest,
  modifiedOldest,
  fileSystem,
  sizeAscending,
  sizeDescending,
}

enum FileNameSortMode { natural, lexicographic }

SortOrder normalizeArchiveSortOrder(SortOrder order) =>
    order == SortOrder.fileSystem ? SortOrder.nameAscending : order;

const sortOrderOptions = <SortOrder>[
  SortOrder.fileSystem,
  SortOrder.nameAscending,
  SortOrder.nameDescending,
  SortOrder.sizeAscending,
  SortOrder.sizeDescending,
  SortOrder.modifiedNewest,
  SortOrder.modifiedOldest,
];

const archiveSortOrderOptions = <SortOrder>[
  SortOrder.nameAscending,
  SortOrder.nameDescending,
  SortOrder.sizeAscending,
  SortOrder.sizeDescending,
  SortOrder.modifiedNewest,
  SortOrder.modifiedOldest,
];
