import { z } from 'zod';

/**
 * Validation schemas for API endpoints using Zod
 * Provides strict input validation and sanitization
 */

// Helper: Bbox validation with coordinate range checks
const BboxSchema = z.string()
  .regex(/^-?\d+\.?\d*,-?\d+\.?\d*,-?\d+\.?\d*,-?\d+\.?\d*$/, 'bbox must be in format: lat_min,lng_min,lat_max,lng_max')
  .refine(bbox => {
    const [latMin, lngMin, latMax, lngMax] = bbox.split(',').map(Number);
    return latMin >= -90 && latMin <= 90 &&
           latMax >= -90 && latMax <= 90 &&
           lngMin >= -180 && lngMin <= 180 &&
           lngMax >= -180 && lngMax <= 180 &&
           latMin < latMax && lngMin < lngMax;
  }, 'Invalid bbox coordinates or ranges');

// Helper: Slug validation (lowercase alphanumeric with dashes)
const SlugSchema = z.string()
  .min(1)
  .max(200)
  .regex(/^[a-z0-9-]+$/, 'Slug must be lowercase alphanumeric with dashes only');

// Helper: CSV list validation (alphanumeric with underscores and commas)
const CsvListSchema = z.string()
  .max(200)
  .regex(/^[a-z0-9_,-]+$/, 'Must be lowercase alphanumeric with underscores, dashes, and commas');

/**
 * Schema for GET /v1/pois query parameters
 */
export const PoisQuerySchema = z.object({
  bbox: BboxSchema,

  city: SlugSchema.default('paris'),

  primary_type: CsvListSchema.optional(),

  subcategory: CsvListSchema.optional(),

  neighbourhood_slug: CsvListSchema.optional(),

  district_slug: CsvListSchema.optional(),

  tags: CsvListSchema.optional(),

  tags_any: CsvListSchema.optional(),

  awards: CsvListSchema.optional(),

  awarded: z.enum(['true', 'false']).optional(),

  fresh: z.enum(['true', 'false']).optional(),

  price: z.coerce.number().int().min(1).max(4).optional(),

  price_min: z.coerce.number().int().min(1).max(4).optional(),

  price_max: z.coerce.number().int().min(1).max(4).optional(),

  rating_min: z.coerce.number().min(0).max(5).optional(),

  rating_max: z.coerce.number().min(0).max(5).optional(),

  sort: z.enum(['gatto', 'price_desc', 'price_asc', 'mentions', 'rating'])
    .default('gatto'),

  limit: z.coerce.number().int().min(1).max(80).default(50),

  lang: z.enum(['fr', 'en']).default('fr')
}).strict(); // Reject unknown parameters

/**
 * Schema for GET /v1/pois/:slug path parameters
 */
export const PoiDetailParamsSchema = z.object({
  slug: SlugSchema
}).strict();

/**
 * Schema for GET /v1/pois/:slug query parameters
 */
export const PoiDetailQuerySchema = z.object({
  lang: z.enum(['fr', 'en']).default('fr')
}).strict();

/**
 * Schema for GET /v1/pois/facets query parameters
 */
export const PoisFacetsQuerySchema = z.object({
  bbox: z.string()
    .regex(/^-?\d+\.?\d*,-?\d+\.?\d*,-?\d+\.?\d*,-?\d+\.?\d*$/)
    .optional(),

  city: SlugSchema.default('paris'),

  primary_type: CsvListSchema.optional(),

  subcategory: CsvListSchema.optional(),

  neighbourhood_slug: CsvListSchema.optional(),

  district_slug: CsvListSchema.optional(),

  tags: CsvListSchema.optional(),

  tags_any: CsvListSchema.optional(),

  awards: CsvListSchema.optional(),

  awarded: z.enum(['true', 'false']).optional(),

  fresh: z.enum(['true', 'false']).optional(),

  price: z.coerce.number().int().min(1).max(4).optional(),

  price_min: z.coerce.number().int().min(1).max(4).optional(),

  price_max: z.coerce.number().int().min(1).max(4).optional(),

  rating_min: z.coerce.number().min(0).max(5).optional(),

  rating_max: z.coerce.number().min(0).max(5).optional(),

  sort: z.enum(['gatto', 'price_desc', 'price_asc', 'mentions', 'rating'])
    .default('gatto')
}).strict();

/**
 * Helper function to format Zod errors for API responses
 */
export function formatZodErrors(zodError) {
  return zodError.errors.map(err => ({
    field: err.path.join('.'),
    message: err.message,
    code: err.code
  }));
}
