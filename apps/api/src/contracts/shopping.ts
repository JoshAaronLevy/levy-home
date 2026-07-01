export type ShoppingListItem = {
  id: number;
  name: string;
  brand?: string;
  quantity: number;
  notes?: string;
  purchased: boolean;
  created?: string;
  updated?: string;
  version?: number;
  categoryId: number | null;
  image?: string;
  storeListings: ShoppingItemStoreListing[];
};

export type ShoppingItemStoreListingProduct = {
  productId?: string;
  upc?: string;
  productPageURI?: string;
  brand?: string;
  name?: string;
  description?: string;
  image?: string;
};

export type ShoppingItemStoreListingAisle = {
  display?: string;
  description?: string;
  number?: string;
  shelfNumber?: string;
  raw?: Record<string, unknown>;
};

export type ShoppingItemStoreListingPrice = {
  regular?: number;
  promo?: number;
};

export type ShoppingItemStoreListingAvailability = {
  status?: string;
  checkedAt?: string;
};

export type ShoppingItemStoreListing = {
  storeId?: number;
  storeName?: string;
  source?: string;
  krogerLocationId?: string;
  product?: ShoppingItemStoreListingProduct;
  aisle?: ShoppingItemStoreListingAisle;
  price?: ShoppingItemStoreListingPrice;
  inventory?: Record<string, unknown>;
  fulfillment?: Record<string, unknown>;
  availability?: ShoppingItemStoreListingAvailability;
  checkedAt?: string;
};

export type ShoppingStore = {
  id: number;
  name: string;
  logo?: string;
};

export type ShoppingCategory = {
  id: number;
  name: string;
};

export type ShoppingListData = {
  items: ShoppingListItem[];
  stores: ShoppingStore[];
  categories: ShoppingCategory[];
};

export type CreateShoppingListItemRequest = {
  name: string;
  brand?: string | null;
  quantity?: number;
  notes?: string | null;
  purchased?: boolean;
  categoryId?: number | null;
  image?: string | null;
  storeListings?: ShoppingItemStoreListing[];
  mutationId?: string;
};

export type UpdateShoppingListItemRequest = {
  name?: string;
  brand?: string | null;
  quantity?: number;
  notes?: string | null;
  purchased?: boolean;
  categoryId?: number | null;
  image?: string | null;
  storeListings?: ShoppingItemStoreListing[];
  mutationId?: string;
};

export type ShoppingListItemLookupResponse = {
  ok: true;
  query: string;
  match: ShoppingListItem | null;
};

export type KrogerProductSearchResponse = {
  ok: boolean;
  query: string;
  generatedAt: string;
  productStatusCode?: number;
  products: KrogerProductSearchResult[];
  error?: string;
};

export type KrogerProductSearchResult = {
  productId: string | null;
  upc: string | null;
  productPageURI: string | null;
  aisles: unknown[];
  brand: string | null;
  name: string | null;
  description: string | null;
  image: string | null;
  storeListings: ShoppingItemStoreListing[];
};

export type ShoppingListMutationResponse = {
  ok: true;
  item: ShoppingListItem;
  mutationId: string;
  generatedAt: string;
};

export type DeleteShoppingListItemResponse = {
  ok: true;
  itemId: number;
  item: ShoppingListItem;
  mutationId: string;
  generatedAt: string;
};
