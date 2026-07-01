import assert from 'node:assert/strict';
import { test } from 'node:test';

import { normalizeKrogerProducts } from '../../../../src/integrations/kroger/productNormalizer.js';

test('normalizeKrogerProducts maps requested product fields and featured large image', () => {
  const products = normalizeKrogerProducts({
    data: [
      {
        productId: '0003700008411',
        upc: '0003700008411',
        productPageURI: '/p/luvs-diapers/0003700008411',
        aisleLocations: [
          {
            bayNumber: '2',
            description: 'Baby',
            number: '8',
          },
        ],
        brand: 'Luvs',
        description: 'Luvs Disposable Baby Diapers',
        images: [
          {
            perspective: 'back',
            featured: false,
            sizes: [
              { size: 'xlarge', url: 'https://example.test/xlarge/back' },
              { size: 'large', url: 'https://example.test/large/back' },
            ],
          },
          {
            perspective: 'front',
            featured: true,
            sizes: [
              { size: 'xlarge', url: 'https://example.test/xlarge/front' },
              { size: 'large', url: 'https://example.test/large/front' },
            ],
          },
        ],
      },
    ],
  });

  assert.deepEqual(products, [
    {
      productId: '0003700008411',
      upc: '0003700008411',
      productPageURI: '/p/luvs-diapers/0003700008411',
      aisles: [
        {
          bayNumber: '2',
          description: 'Baby',
          number: '8',
        },
      ],
      brand: 'Luvs',
      name: 'Luvs Disposable Baby Diapers',
      description: 'Luvs Disposable Baby Diapers',
      image: 'https://example.test/large/front',
      storeListings: [],
    },
  ]);
});
