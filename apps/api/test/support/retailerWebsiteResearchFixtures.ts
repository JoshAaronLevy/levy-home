import type { RetailerWebsiteStoreKey } from '../../src/services/shopping/retailerWebsiteScope.js';

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
  },
  {
    name: 'King Soopers confirmed low stock',
    storeKey: 'king_soopers_wildcat_reserve',
    renderedStoreText: 'King Soopers 2205 W Wildcat Reserve Pkwy Highlands Ranch CO',
    outcome: 'low_stock',
    matchStatus: 'matched',
    hasPrice: true,
    hasAisle: true,
  },
  {
    name: 'Target confirmed out of stock',
    storeKey: 'target_highlands_ranch',
    renderedStoreText: '1365 Sgt Jon Stiles Dr, Highlands Ranch, CO',
    outcome: 'out_of_stock',
    matchStatus: 'matched',
    hasPrice: false,
    hasAisle: false,
  },
  {
    name: 'King Soopers no match',
    storeKey: 'king_soopers_wildcat_reserve',
    renderedStoreText: '2205 W Wildcat Reserve Pkwy Highlands Ranch CO',
    outcome: 'unknown',
    matchStatus: 'no_match',
    hasPrice: false,
    hasAisle: false,
  },
  {
    name: 'Target ambiguous match',
    storeKey: 'target_highlands_ranch',
    renderedStoreText: '1365 Sgt Jon Stiles Dr Highlands Ranch CO',
    outcome: 'unknown',
    matchStatus: 'ambiguous',
    hasPrice: false,
    hasAisle: false,
  },
  {
    name: 'Target mismatched store',
    storeKey: 'target_highlands_ranch',
    renderedStoreText: 'Target another location',
    outcome: 'unknown',
    matchStatus: 'store_unconfirmed',
    hasPrice: false,
    hasAisle: false,
  },
  {
    name: 'King Soopers missing price',
    storeKey: 'king_soopers_wildcat_reserve',
    renderedStoreText: '2205 W Wildcat Reserve Pkwy Highlands Ranch CO',
    outcome: 'in_stock',
    matchStatus: 'matched',
    hasPrice: false,
    hasAisle: true,
  },
  {
    name: 'Target missing aisle',
    storeKey: 'target_highlands_ranch',
    renderedStoreText: '1365 Sgt Jon Stiles Dr Highlands Ranch CO',
    outcome: 'in_stock',
    matchStatus: 'matched',
    hasPrice: true,
    hasAisle: false,
  },
  {
    name: 'King Soopers blocked page',
    storeKey: 'king_soopers_wildcat_reserve',
    renderedStoreText: '',
    outcome: 'unknown',
    matchStatus: 'website_error',
    hasPrice: false,
    hasAisle: false,
  },
  {
    name: 'Target domain scope violation',
    storeKey: 'target_highlands_ranch',
    renderedStoreText: '',
    outcome: 'unknown',
    matchStatus: 'domain_scope_failure',
    hasPrice: false,
    hasAisle: false,
  },
];
