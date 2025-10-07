# POI Endpoints Documentation

## Overview

The POI (Points of Interest) endpoints provide access to location-based data with multi-language support, advanced filtering, and optimized image variants.

## Base URL
```
https://api.gatto.city/v1
```

---

## 📍 GET /v1/poi

Retrieve a paginated list of Points of Interest with filtering and sorting options.

### Query Parameters

#### **Filters**
| Parameter | Type | Default | Description | Example |
|-----------|------|---------|-------------|---------|
| `city` | string | `paris` | City slug | `?city=paris` |
| `category` | string | - | POI category | `?category=restaurant` |
| `price` | string | - | Price level | `?price=€€` |
| `district_slug` | string | - | District filter | `?district_slug=paris-11e-arrondissement` |
| `neighbourhood_slug` | string | - | Neighbourhood filter | `?neighbourhood_slug=saint-ambroise` |
| `tags` | string | - | Comma-separated tags | `?tags=brunch,terrace` |

#### **Display Options**
| Parameter | Type | Default | Description | Example |
|-----------|------|---------|-------------|---------|
| `view` | enum | `card` | Response format: `card` \| `detail` | `?view=detail` |
| `segment` | enum | - | Sorting segment: `digital` \| `awarded` \| `fresh` | `?segment=digital` |
| `lang` | enum | `fr` | Language: `fr` \| `en` | `?lang=en` |
| `fields` | string | - | Field projection (comma-separated) | `?fields=name,photos,scores` |

#### **Pagination**
| Parameter | Type | Default | Description | Example |
|-----------|------|---------|-------------|---------|
| `limit` | integer | `24` | Results per page (max: 50) | `?limit=12` |
| `cursor` | string | - | Pagination cursor (base64) | `?cursor=MTI=` |

### Price Levels
- `€` - Inexpensive
- `€€` - Moderate  
- `€€€` - Expensive
- `€€€€` - Very Expensive

### Sorting Segments
- **Default**: Best Gatto score first
- `digital`: Sorted by digital score DESC
- `awarded`: Sorted by awards bonus DESC, then Gatto score DESC
- `fresh`: Sorted by freshness bonus DESC, then Gatto score DESC

### Response Format

#### Card View (`view=card`)
```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "79bcbc1b-2867-441d-a438-399cf880ba3d",
        "slug": "le-train-bleu",
        "name": "Le Train Bleu",
        "category": "restaurant",
        "district": "Paris 12e Arrondissement",
        "neighbourhood": "Quartier des Quinze-Vingts",
        "photo": {
          "variants": [
            {
              "variant_key": "card_sq@1x",
              "format": "avif",
              "url": "https://cdn.gatto.city/.../card_sq@1x.avif",
              "width": 256,
              "height": 256
            },
            {
              "variant_key": "card_sq@2x",
              "format": "avif",
              "url": "https://cdn.gatto.city/.../card_sq@2x.avif",
              "width": 512,
              "height": 512
            },
            {
              "variant_key": "card_sq@1x",
              "format": "webp",
              "url": "https://cdn.gatto.city/.../card_sq@1x.webp",
              "width": 256,
              "height": 256
            },
            {
              "variant_key": "card_sq@2x",
              "format": "webp",
              "url": "https://cdn.gatto.city/.../card_sq@2x.webp",
              "width": 512,
              "height": 512
            }
          ],
          "width": 256,
          "height": 256,
          "dominant_color": "#825c3a",
          "blurhash": "LHGR6fMvAJjE}kt7E2ozIUt9ITkD"
        },
        "score": 38.1,
        "scores": {
          "gatto": 38.1,
          "digital": 21.1,
          "awards_bonus": 15,
          "freshness_bonus": 2
        },
        "rating": {
          "google": 4.4,
          "reviews_count": 15873
        },
        "sources_count": 5,
        "sources_sample": [
          {
            "domain": "fr.gaultmillau.com",
            "favicon": "https://www.google.com/s2/favicons?domain=fr.gaultmillau.com&sz=64"
          }
        ]
      }
    ],
    "next_cursor": "MjQ=",
    "previous_cursor": null
  },
  "timestamp": "2025-01-15T10:30:00.000Z"
}
```

#### Detail View (`view=detail`)
Card view + additional fields:
- `summary`: AI-generated description
- `coords`: `{ lat, lng }`
- `price_level`: Price level enum
- `opening_hours`: Opening hours JSON
- `photos`: `{ primary, gallery }` instead of single `photo`

### Examples

```bash
# Basic list
curl "https://api.gatto.city/v1/poi"

# Restaurants in Paris 11th district
curl "https://api.gatto.city/v1/poi?category=restaurant&district_slug=paris-11e-arrondissement"

# Digital segment with detailed view
curl "https://api.gatto.city/v1/poi?segment=digital&view=detail&limit=6"

# Filter by tags and price
curl "https://api.gatto.city/v1/poi?tags=brunch,terrace&price=€€&lang=en"

# Pagination
curl "https://api.gatto.city/v1/poi?cursor=MjQ=&limit=12"
```

---

## 📍 GET /v1/poi/:slug

Retrieve detailed information for a specific POI.

### Parameters
| Parameter | Type | Description |
|-----------|------|-------------|
| `slug` | string | POI slug (multi-language support) |
| `lang` | enum | Language: `fr` \| `en` (query param) |

### Response Format
```json
{
  "success": true,
  "data": {
    "id": "79bcbc1b-2867-441d-a438-399cf880ba3d",
    "slug": "le-train-bleu",
    "name": "Le Train Bleu",
    "category": "restaurant",
    "city": "Paris",
    "district": "Paris 12e Arrondissement",
    "neighbourhood": "Quartier des Quinze-Vingts",
    "coords": {
      "lat": 48.84469,
      "lng": 2.37341
    },
    "price_level": "PRICE_LEVEL_EXPENSIVE",
    "tags_keys": {
      "ambiance": ["historic", "elegant"],
      "meal_types": ["dinner", "lunch"],
      "cuisines": ["french"]
    },
    "summary": "Historic Belle Époque restaurant in Gare de Lyon...",
    "opening_hours": {
      "periods": [
        {
          "open": { "day": 0, "time": "1130" },
          "close": { "day": 0, "time": "2300" }
        }
      ]
    },
    "photos": {
      "primary": {
        "variants": [
          {
            "variant_key": "detail@1x",
            "format": "avif",
            "url": "https://cdn.gatto.city/.../detail@1x.avif",
            "width": 576,
            "height": 432
          },
          {
            "variant_key": "detail@2x",
            "format": "avif",
            "url": "https://cdn.gatto.city/.../detail@2x.avif",
            "width": 1152,
            "height": 864
          }
        ],
        "width": 576,
        "height": 432,
        "dominant_color": "#825c3a",
        "blurhash": "LHGR6fMvAJjE}kt7E2ozIUt9ITkD"
      },
      "gallery": [
        {
          "variants": [
            {
              "variant_key": "thumb_small@1x",
              "format": "avif",
              "url": "https://cdn.gatto.city/.../thumb_small@1x.avif",
              "width": 182,
              "height": 128
            }
          ],
          "width": 182,
          "height": 128,
          "dominant_color": "#3a4832",
          "blurhash": "L8E2C4xu9F4n_3t7t7of~qj[WBay"
        }
      ]
    },
    "scores": {
      "gatto": 38.1,
      "digital": 21.1,
      "awards_bonus": 15,
      "freshness_bonus": 2,
      "calculated_at": "2024-12-15T14:30:00.000Z"
    },
    "rating": {
      "google": 4.4,
      "reviews_count": 15873
    },
    "mentions": [
      {
        "domain": "timeout.fr",
        "favicon": "https://www.google.com/s2/favicons?domain=timeout.fr&sz=64",
        "title": "Le Train Bleu: A Belle Époque Gem",
        "excerpt": "Historic restaurant with stunning Art Nouveau decor...",
        "url": "https://timeout.fr/paris/restaurants/le-train-bleu"
      }
    ],
    "breadcrumb": [
      {
        "label": "Paris",
        "href": "/paris"
      },
      {
        "label": "Restaurants", 
        "href": "/paris/restaurants"
      },
      {
        "label": "Paris 12e Arrondissement",
        "href": "/paris/restaurants/paris-12e-arrondissement"
      }
    ]
  },
  "timestamp": "2025-01-15T10:30:00.000Z"
}
```

### Examples

```bash
# Get POI by French slug
curl "https://api.gatto.city/v1/poi/le-train-bleu"

# Get POI with English content
curl "https://api.gatto.city/v1/poi/le-train-bleu?lang=en"
```

---

## 🖼️ Image Variants

### Available Variants
- **card_sq@1x**: 256×256 (card listings)
- **card_sq@2x**: 512×512 (retina card listings) 
- **detail@1x**: 576×432 (detail page hero)
- **detail@2x**: 1152×864 (retina detail hero)
- **thumb_small@1x**: 182×128 (gallery thumbnails)
- **thumb_small@2x**: 364×256 (retina thumbnails)

### Format Priority
1. **AVIF** (best compression, modern browsers)
2. **WebP** (good compression, wide support)
3. **JPG** (fallback, universal support) - *Note: Currently not generated*

### Image Metadata
- **dominant_color**: Hex color for placeholder backgrounds
- **blurhash**: Encoded image preview for loading states
- **width/height**: Dimensions for layout optimization

---

## ⚡ Performance Features

### Caching
- **HTTP Cache**: `Cache-Control: public, max-age=300` (5 minutes)
- **ETag**: Automatic conditional requests

### Rate Limiting  
- **Limit**: 100 requests per minute per IP
- **Response**: `429 Too Many Requests` when exceeded

### Optimization
- **Batch queries**: Minimizes database round-trips
- **Image variants**: Modern formats with multiple resolutions
- **Pagination**: Cursor-based for consistent results

---

## 🌍 Multi-Language Support

### Language Detection
1. Query parameter: `?lang=fr|en`
2. Default: `fr` (French)

### Localized Fields
- `name`: POI name
- `slug`: URL-friendly identifier  
- `summary`: AI-generated description
- `breadcrumb`: Navigation labels

### Fallback Logic
```
Primary: field_${lang} (e.g., name_fr)
Fallback: field_${other_lang} (e.g., name_en)
Legacy: field (e.g., name)
```

---

## 🔍 Common Use Cases

### Homepage POI Feed
```bash
curl "https://api.gatto.city/v1/poi?segment=digital&limit=6&view=card"
```

### Restaurant Listing Page
```bash
curl "https://api.gatto.city/v1/poi?category=restaurant&city=paris&limit=24&view=card"
```

### District Page
```bash
curl "https://api.gatto.city/v1/poi?district_slug=paris-11e-arrondissement&limit=24"
```

### Search Results
```bash
curl "https://api.gatto.city/v1/poi?tags=brunch&price=€€&neighbourhood_slug=marais"
```

### POI Detail Page
```bash
curl "https://api.gatto.city/v1/poi/le-train-bleu?lang=fr"
```

---

## ❌ Error Handling

### Error Response Format
```json
{
  "success": false,
  "error": {
    "message": "POI not found",
    "details": null,
    "timestamp": "2025-01-15T10:30:00.000Z"
  }
}
```

### Common Error Codes
- `400`: Bad request (invalid parameters)
- `404`: POI not found (detail endpoint)
- `429`: Rate limit exceeded
- `500`: Internal server error