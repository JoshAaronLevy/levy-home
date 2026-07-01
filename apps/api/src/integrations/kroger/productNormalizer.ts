import type {
  KrogerProductSearchResult,
  ShoppingItemStoreListing,
} from '../../contracts.js';

export type NormalizedKrogerProduct = KrogerProductSearchResult;

export type KrogerListingContext = {
  storeId: number;
  storeName: string;
  locationId: string;
  checkedAt: string;
};

export function normalizeKrogerProducts(
  productResponseBody: unknown,
  context?: KrogerListingContext,
): NormalizedKrogerProduct[] {
  if (!isRecord(productResponseBody) || !Array.isArray(productResponseBody.data)) {
    return [];
  }

  return productResponseBody.data
    .filter(isRecord)
    .map((product) => {
      const description = stringValue(product.description);
      const productId = stringValue(product.productId);
      const upc = stringValue(product.upc);
      const productPageURI = stringValue(product.productPageURI);
      const brand = stringValue(product.brand);
      const image = featuredLargeImageURL(product.images);
      const aisles = Array.isArray(product.aisleLocations) ? product.aisleLocations : [];
      const firstItem = Array.isArray(product.items) ? product.items.find(isRecord) : undefined;

      return {
        productId,
        upc,
        productPageURI,
        aisles,
        brand,
        name: description,
        description,
        image,
        storeListings: context
          ? [
              krogerStoreListing({
                context,
                productId,
                upc,
                productPageURI,
                brand,
                description,
                image,
                aisles,
                firstItem,
              }),
            ]
          : [],
      };
    });
}

function krogerStoreListing(options: {
  context: KrogerListingContext;
  productId: string | null;
  upc: string | null;
  productPageURI: string | null;
  brand: string | null;
  description: string | null;
  image: string | null;
  aisles: unknown[];
  firstItem?: Record<string, unknown>;
}): ShoppingItemStoreListing {
  const firstAisle = options.aisles.find(isRecord);
  const price = isRecord(options.firstItem?.price) ? options.firstItem.price : undefined;
  const inventory = isRecord(options.firstItem?.inventory) ? options.firstItem.inventory : undefined;
  const listing: ShoppingItemStoreListing = {
    storeId: options.context.storeId,
    storeName: options.context.storeName,
    krogerLocationId: options.context.locationId,
    product: {
      ...(options.productId ? { productId: options.productId } : {}),
      ...(options.upc ? { upc: options.upc } : {}),
      ...(options.productPageURI ? { productPageURI: options.productPageURI } : {}),
      ...(options.brand ? { brand: options.brand } : {}),
      ...(options.description ? { name: options.description, description: options.description } : {}),
      ...(options.image ? { image: options.image } : {}),
    },
    ...(firstAisle ? { aisle: krogerAisle(firstAisle) } : {}),
    ...(price ? { price: krogerPrice(price) } : {}),
    ...(inventory ? { inventory } : {}),
  };

  return listing;
}

function krogerAisle(aisle: Record<string, unknown>): NonNullable<ShoppingItemStoreListing['aisle']> {
  const number = stringValue(aisle.number);
  const description = stringValue(aisle.description);
  const shelfNumber = stringValue(aisle.shelfNumber);
  const displayParts = [number, shelfNumber].filter((value): value is string => Boolean(value));

  return {
    ...(displayParts.length > 0 ? { display: displayParts.join(':') } : {}),
    ...(description ? { description } : {}),
    ...(number ? { number } : {}),
    ...(shelfNumber ? { shelfNumber } : {}),
    raw: aisle,
  };
}

function krogerPrice(price: Record<string, unknown>): NonNullable<ShoppingItemStoreListing['price']> {
  const regular = numberValue(price.regular);
  const promo = numberValue(price.promo);

  return {
    ...(regular !== undefined ? { regular } : {}),
    ...(promo !== undefined ? { promo } : {}),
  };
}

function featuredLargeImageURL(value: unknown): string | null {
  if (!Array.isArray(value)) {
    return null;
  }

  const featuredImage = value.filter(isRecord).find((image) => image.featured === true);

  if (!featuredImage || !Array.isArray(featuredImage.sizes)) {
    return null;
  }

  const largeSize = featuredImage.sizes
    .filter(isRecord)
    .find((size) => size.size === 'large');

  if (typeof largeSize?.url === 'string') {
    return largeSize.url;
  }

  const fallbackSize = featuredImage.sizes[1];

  return isRecord(fallbackSize) && typeof fallbackSize.url === 'string' ? fallbackSize.url : null;
}

function stringValue(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value : null;
}

function numberValue(value: unknown): number | undefined {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === 'string' && value.trim()) {
    const parsed = Number(value);

    return Number.isFinite(parsed) ? parsed : undefined;
  }

  return undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}
