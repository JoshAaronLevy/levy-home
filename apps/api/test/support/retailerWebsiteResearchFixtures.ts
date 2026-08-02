import type { RetailerWebsiteStoreKey } from '../../src/services/shopping/retailerWebsiteScope.js';
import type { RetailerWebsiteRenderedPageEvidence } from '../../src/services/shopping/retailerWebsiteResearcher.js';

export type RetailerWebsiteResearchFixture = {
  name: string;
  storeKey: RetailerWebsiteStoreKey;
  renderedStoreText: string;
  outcome: 'in_stock' | 'low_stock' | 'out_of_stock' | 'unknown';
  matchStatus:
    | 'matched'
    | 'no_match'
    | 'ambiguous'
    | 'store_unconfirmed'
    | 'website_error'
    | 'domain_scope_failure';
  hasPrice: boolean;
  hasAisle: boolean;
  evidence: RetailerWebsiteRenderedPageEvidence;
};

export const retailerWebsiteResearchFixtures: readonly RetailerWebsiteResearchFixture[] = [
  {
    name: 'Target confirmed in stock',
    storeKey: 'target_highlands_ranch',
    renderedStoreText: 'Target 1365 Sgt Jon Stiles Dr Highlands Ranch CO',
    outcome: 'in_stock',
    matchStatus: 'matched',
    hasPrice: true,
    hasAisle: true,
    evidence: {
      outcome: 'matched',
      navigation: { url: 'https://www.target.com/s', method: 'GET' },
      renderedStoreText: 'Target 1365 Sgt Jon Stiles Dr Highlands Ranch CO',
      renderedAvailabilityText: 'In stock',
      product: { name: 'Fixture Target milk', brand: 'Fixture Farms', upc: '000111222333' },
      price: { regular: 3.99, promo: 2.99 },
      aisle: { display: 'A12', number: '12', shelfNumber: 'A' },
    },
  },
  {
    name: 'King Soopers confirmed low stock',
    storeKey: 'king_soopers_wildcat_reserve',
    renderedStoreText: 'King Soopers 2205 W Wildcat Reserve Pkwy Highlands Ranch CO',
    outcome: 'low_stock',
    matchStatus: 'matched',
    hasPrice: true,
    hasAisle: true,
    evidence: {
      outcome: 'matched',
      navigation: { url: 'https://www.kingsoopers.com/search', method: 'GET' },
      renderedStoreText: 'King Soopers 2205 W Wildcat Reserve Pkwy Highlands Ranch CO',
      renderedAvailabilityText: 'Limited stock',
      product: { name: 'Fixture King Soopers eggs' },
      price: { regular: 4.29 },
      aisle: { display: 'Aisle 4', number: '4' },
    },
  },
  {
    name: 'Target confirmed out of stock',
    storeKey: 'target_highlands_ranch',
    renderedStoreText: '1365 Sgt Jon Stiles Dr, Highlands Ranch, CO',
    outcome: 'out_of_stock',
    matchStatus: 'matched',
    hasPrice: false,
    hasAisle: false,
    evidence: {
      outcome: 'matched',
      navigation: { url: 'https://target.com/p/fixture-product', method: 'GET' },
      renderedStoreText: '1365 Sgt Jon Stiles Dr, Highlands Ranch, CO',
      renderedAvailabilityText: 'Out of stock',
      product: { name: 'Fixture Target coffee' },
    },
  },
  {
    name: 'King Soopers no match',
    storeKey: 'king_soopers_wildcat_reserve',
    renderedStoreText: '2205 W Wildcat Reserve Pkwy Highlands Ranch CO',
    outcome: 'unknown',
    matchStatus: 'no_match',
    hasPrice: false,
    hasAisle: false,
    evidence: {
      outcome: 'no_match',
      navigation: { url: 'https://kingsoopers.com/search', method: 'GET' },
      renderedStoreText: '2205 W Wildcat Reserve Pkwy Highlands Ranch CO',
    },
  },
  {
    name: 'Target ambiguous match',
    storeKey: 'target_highlands_ranch',
    renderedStoreText: '1365 Sgt Jon Stiles Dr Highlands Ranch CO',
    outcome: 'unknown',
    matchStatus: 'ambiguous',
    hasPrice: false,
    hasAisle: false,
    evidence: {
      outcome: 'ambiguous',
      navigation: { url: 'https://www.target.com/s', method: 'GET' },
      renderedStoreText: '1365 Sgt Jon Stiles Dr Highlands Ranch CO',
    },
  },
  {
    name: 'Target mismatched store',
    storeKey: 'target_highlands_ranch',
    renderedStoreText: 'Target another location',
    outcome: 'unknown',
    matchStatus: 'store_unconfirmed',
    hasPrice: false,
    hasAisle: false,
    evidence: {
      outcome: 'matched',
      navigation: { url: 'https://www.target.com/p/fixture-product', method: 'GET' },
      renderedStoreText: 'Target another location',
      renderedAvailabilityText: 'In stock',
      product: { name: 'Fixture Target product' },
    },
  },
  {
    name: 'King Soopers missing price',
    storeKey: 'king_soopers_wildcat_reserve',
    renderedStoreText: '2205 W Wildcat Reserve Pkwy Highlands Ranch CO',
    outcome: 'in_stock',
    matchStatus: 'matched',
    hasPrice: false,
    hasAisle: true,
    evidence: {
      outcome: 'matched',
      navigation: { url: 'https://www.kingsoopers.com/search', method: 'GET' },
      renderedStoreText: '2205 W Wildcat Reserve Pkwy Highlands Ranch CO',
      renderedAvailabilityText: 'In stock',
      product: { name: 'Fixture King Soopers fruit' },
      aisle: { display: 'Produce' },
    },
  },
  {
    name: 'Target missing aisle',
    storeKey: 'target_highlands_ranch',
    renderedStoreText: '1365 Sgt Jon Stiles Dr Highlands Ranch CO',
    outcome: 'in_stock',
    matchStatus: 'matched',
    hasPrice: true,
    hasAisle: false,
    evidence: {
      outcome: 'matched',
      navigation: { url: 'https://target.com/p/fixture-product', method: 'GET' },
      renderedStoreText: '1365 Sgt Jon Stiles Dr Highlands Ranch CO',
      renderedAvailabilityText: 'Available for pickup',
      product: { name: 'Fixture Target bread' },
      price: { promo: 1.99 },
    },
  },
  {
    name: 'King Soopers blocked page',
    storeKey: 'king_soopers_wildcat_reserve',
    renderedStoreText: '',
    outcome: 'unknown',
    matchStatus: 'website_error',
    hasPrice: false,
    hasAisle: false,
    evidence: {
      outcome: 'website_error',
      navigation: { url: 'https://www.kingsoopers.com/search', method: 'GET' },
    },
  },
  {
    name: 'Target domain scope violation',
    storeKey: 'target_highlands_ranch',
    renderedStoreText: '',
    outcome: 'unknown',
    matchStatus: 'domain_scope_failure',
    hasPrice: false,
    hasAisle: false,
    evidence: {
      outcome: 'matched',
      navigation: { url: 'https://www.example.com/product', method: 'GET' },
      renderedStoreText: '1365 Sgt Jon Stiles Dr Highlands Ranch CO',
      renderedAvailabilityText: 'In stock',
      product: { name: 'Fixture untrusted product' },
    },
  },
];
