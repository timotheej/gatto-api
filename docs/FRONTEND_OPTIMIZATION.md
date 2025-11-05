# 🚀 Optimisations Frontend - Map + Listing POIs

**Objectif** : Performances maximales pour affichage simultané map + liste (style Airbnb)

---

## 📊 Architecture Recommandée

### Flux de données optimal

```
User move map
    ↓
Debounce 300ms
    ↓
Calculate new bbox
    ↓
Check SWR cache → HIT ? Return cached
    ↓ MISS
API call /v1/pois?bbox=...
    ↓
Cache response (SWR)
    ↓
Update map markers + list simultaneously
```

---

## 🎯 Stratégie 1 : Cache Côté Client (PRIORITÉ 1)

### Option A : SWR (Recommandé pour Next.js)

```bash
npm install swr
```

```typescript
// hooks/usePOIs.ts
import useSWR from 'swr';

interface POIsParams {
  bbox: string;
  city?: string;
  categories?: string[];
  // ... autres filtres
}

const fetcher = async (url: string) => {
  const res = await fetch(url, {
    headers: {
      'x-api-key': process.env.NEXT_PUBLIC_API_KEY!
    }
  });
  if (!res.ok) throw new Error('Failed to fetch');
  return res.json();
};

export function usePOIs(params: POIsParams) {
  // Générer une clé stable pour le cache
  const cacheKey = params.bbox
    ? `/v1/pois?${new URLSearchParams(params as any).toString()}`
    : null;

  const { data, error, isLoading, mutate } = useSWR(
    cacheKey,
    fetcher,
    {
      // ✅ Cache 5 minutes (même durée que l'API)
      dedupingInterval: 5 * 60 * 1000,

      // ✅ Garde les données précédentes pendant le loading
      keepPreviousData: true,

      // ✅ Revalidation en arrière-plan
      revalidateOnFocus: false,
      revalidateOnReconnect: true,

      // ✅ Pas de retry si bbox invalide
      shouldRetryOnError: false,
    }
  );

  return {
    pois: data?.data || [],
    isLoading,
    isError: error,
    mutate // Pour forcer un refresh si besoin
  };
}
```

**Gains attendus** :
- 🚀 **0ms** si bbox déjà en cache
- 🚀 **~20-30ms** si bbox proche (cache hit API)
- 🚀 **~130ms** sinon (cache miss API)

---

### Option B : TanStack Query (React Query)

```bash
npm install @tanstack/react-query
```

```typescript
// app/providers.tsx
'use client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 5 * 60 * 1000, // 5 minutes
      gcTime: 10 * 60 * 1000,   // 10 minutes
    },
  },
});

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <QueryClientProvider client={queryClient}>
      {children}
    </QueryClientProvider>
  );
}

// hooks/usePOIs.ts
import { useQuery } from '@tanstack/react-query';

export function usePOIs(params: POIsParams) {
  return useQuery({
    queryKey: ['pois', params],
    queryFn: async () => {
      const url = new URL('https://api.gatto.city/v1/pois');
      Object.entries(params).forEach(([key, value]) => {
        if (value) url.searchParams.set(key, String(value));
      });

      const res = await fetch(url, {
        headers: { 'x-api-key': process.env.NEXT_PUBLIC_API_KEY! }
      });

      if (!res.ok) throw new Error('Failed to fetch POIs');
      return res.json();
    },
    enabled: !!params.bbox, // Ne lance pas si pas de bbox
    staleTime: 5 * 60 * 1000,
    placeholderData: (previousData) => previousData, // Garde les anciennes données
  });
}
```

---

## 🗺️ Stratégie 2 : Optimisations Map

### Mapbox GL JS (Recommandé)

```typescript
// components/Map.tsx
'use client';
import { useEffect, useRef, useState } from 'react';
import mapboxgl from 'mapbox-gl';
import 'mapbox-gl/dist/mapbox-gl.css';

export function Map({ pois, onBboxChange }) {
  const mapContainer = useRef<HTMLDivElement>(null);
  const map = useRef<mapboxgl.Map | null>(null);
  const markersRef = useRef<mapboxgl.Marker[]>([]);

  useEffect(() => {
    if (!mapContainer.current) return;

    // Initialiser la map
    map.current = new mapboxgl.Map({
      container: mapContainer.current,
      style: 'mapbox://styles/mapbox/streets-v12',
      center: [2.3522, 48.8566], // Paris
      zoom: 13,
      // ✅ Performance optimizations
      maxTileCacheSize: 50,
      preserveDrawingBuffer: false,
      trackResize: true,
    });

    // ✅ Debounce du moveend pour éviter trop d'appels API
    let moveTimeout: NodeJS.Timeout;
    map.current.on('moveend', () => {
      clearTimeout(moveTimeout);
      moveTimeout = setTimeout(() => {
        const bounds = map.current!.getBounds();
        const bbox = [
          bounds.getSouthWest().lng,
          bounds.getSouthWest().lat,
          bounds.getNorthEast().lng,
          bounds.getNorthEast().lat,
        ].join(',');

        onBboxChange(bbox);
      }, 300); // 300ms debounce
    });

    return () => {
      map.current?.remove();
    };
  }, []);

  // ✅ Optimisation : Update markers uniquement si pois changent
  useEffect(() => {
    if (!map.current) return;

    // Supprimer les anciens markers
    markersRef.current.forEach(marker => marker.remove());
    markersRef.current = [];

    // ✅ Utiliser des markers HTML simples (pas de popup tant qu'on clique pas)
    pois.forEach((poi) => {
      const el = document.createElement('div');
      el.className = 'custom-marker';
      el.style.backgroundImage = `url(${poi.primary_photo?.variants?.card_sq?.cdn_url})`;
      el.style.width = '40px';
      el.style.height = '40px';
      el.style.borderRadius = '50%';
      el.style.cursor = 'pointer';
      el.style.backgroundSize = 'cover';

      // ✅ Lazy load popup (seulement au clic)
      el.addEventListener('click', () => {
        new mapboxgl.Popup({ offset: 25 })
          .setLngLat([poi.lng, poi.lat])
          .setHTML(`
            <div class="poi-popup">
              <h3>${poi.name}</h3>
              <p>${poi.city_name}</p>
            </div>
          `)
          .addTo(map.current!);
      });

      const marker = new mapboxgl.Marker(el)
        .setLngLat([poi.lng, poi.lat])
        .addTo(map.current);

      markersRef.current.push(marker);
    });
  }, [pois]);

  return <div ref={mapContainer} className="w-full h-full" />;
}
```

**Optimisations clés** :
- ✅ Debounce 300ms sur `moveend`
- ✅ Markers HTML simples (pas de DOM lourd)
- ✅ Popups lazy-loaded (au clic seulement)
- ✅ Cleanup des anciens markers

---

### Alternative : Google Maps avec clustering

```typescript
import { GoogleMap, useLoadScript, MarkerClusterer } from '@react-google-maps/api';

export function Map({ pois, onBboxChange }) {
  const { isLoaded } = useLoadScript({
    googleMapsApiKey: process.env.NEXT_PUBLIC_GOOGLE_MAPS_KEY!,
  });

  const onBoundsChanged = useDebouncedCallback(() => {
    if (!mapRef.current) return;

    const bounds = mapRef.current.getBounds();
    const ne = bounds.getNorthEast();
    const sw = bounds.getSouthWest();
    const bbox = `${sw.lng()},${sw.lat()},${ne.lng()},${ne.lat()}`;

    onBboxChange(bbox);
  }, 300);

  if (!isLoaded) return <div>Loading map...</div>;

  return (
    <GoogleMap
      zoom={13}
      center={{ lat: 48.8566, lng: 2.3522 }}
      onBoundsChanged={onBoundsChanged}
      options={{
        // ✅ Performance optimizations
        gestureHandling: 'greedy',
        disableDefaultUI: false,
        zoomControl: true,
        mapTypeControl: false,
        streetViewControl: false,
      }}
    >
      {/* ✅ Clustering pour > 50 POIs */}
      <MarkerClusterer
        options={{
          imagePath: '/images/cluster/m',
          gridSize: 60,
          maxZoom: 15,
        }}
      >
        {(clusterer) =>
          pois.map((poi) => (
            <Marker
              key={poi.id}
              position={{ lat: poi.lat, lng: poi.lng }}
              clusterer={clusterer}
              icon={{
                url: poi.primary_photo?.variants?.card_sq?.cdn_url,
                scaledSize: new google.maps.Size(40, 40),
              }}
            />
          ))
        }
      </MarkerClusterer>
    </GoogleMap>
  );
}
```

---

## 📜 Stratégie 3 : Liste Virtualisée

### React Virtualized (Recommandé)

```bash
npm install react-window
```

```typescript
// components/POIList.tsx
import { FixedSizeList as List } from 'react-window';
import AutoSizer from 'react-virtualized-auto-sizer';

interface POIListProps {
  pois: POI[];
  onPOIClick: (poi: POI) => void;
}

export function POIList({ pois, onPOIClick }: POIListProps) {
  // ✅ Render seulement les items visibles (au lieu de tous)
  const Row = ({ index, style }) => {
    const poi = pois[index];

    return (
      <div
        style={style}
        className="poi-card cursor-pointer"
        onClick={() => onPOIClick(poi)}
      >
        <img
          src={poi.primary_photo?.variants?.card_sq?.cdn_url}
          alt={poi.name}
          loading="lazy" // ✅ Lazy load images
          className="w-24 h-24 object-cover rounded"
        />
        <div className="flex-1">
          <h3 className="font-semibold">{poi.name}</h3>
          <p className="text-sm text-gray-600">{poi.city_name}</p>
          <div className="flex items-center gap-1">
            <span>⭐ {poi.rating?.toFixed(1)}</span>
            <span>💰 {'€'.repeat(poi.price_level_numeric || 1)}</span>
          </div>
        </div>
      </div>
    );
  };

  return (
    <AutoSizer>
      {({ height, width }) => (
        <List
          height={height}
          width={width}
          itemCount={pois.length}
          itemSize={120} // Hauteur d'une card
          overscanCount={5} // Précharge 5 items avant/après le viewport
        >
          {Row}
        </List>
      )}
    </AutoSizer>
  );
}
```

**Gains** :
- ✅ Render seulement ~10 items au lieu de 80
- ✅ Scroll fluide même avec 1000 POIs
- ✅ Moins de DOM nodes = moins de mémoire

---

## ⚡ Stratégie 4 : Optimisations React

### Mémoization

```typescript
// components/MapAndList.tsx
'use client';
import { useState, useMemo, useCallback } from 'react';
import { usePOIs } from '@/hooks/usePOIs';

export function MapAndList() {
  const [bbox, setBbox] = useState<string>('');
  const [filters, setFilters] = useState({ categories: [], price: [] });

  // ✅ Fetch POIs avec SWR
  const { pois, isLoading } = usePOIs({ bbox, ...filters });

  // ✅ Mémoize bbox change handler
  const handleBboxChange = useCallback((newBbox: string) => {
    setBbox(newBbox);
  }, []);

  // ✅ Mémoize POI click handler
  const handlePOIClick = useCallback((poi: POI) => {
    // Zoom sur le POI sur la map
    console.log('Selected POI:', poi);
  }, []);

  // ✅ Filtrer les POIs côté client si besoin (rapide)
  const filteredPOIs = useMemo(() => {
    if (!filters.categories.length) return pois;
    return pois.filter(poi =>
      filters.categories.includes(poi.primary_type)
    );
  }, [pois, filters]);

  return (
    <div className="flex h-screen">
      {/* Map : 60% */}
      <div className="w-3/5 relative">
        <Map
          pois={filteredPOIs}
          onBboxChange={handleBboxChange}
        />
        {isLoading && (
          <div className="absolute top-4 left-1/2 -translate-x-1/2 bg-white px-4 py-2 rounded shadow">
            Loading...
          </div>
        )}
      </div>

      {/* Liste : 40% */}
      <div className="w-2/5 overflow-hidden">
        <div className="p-4">
          <h2 className="text-xl font-bold">
            {filteredPOIs.length} résultats
          </h2>
        </div>
        <POIList
          pois={filteredPOIs}
          onPOIClick={handlePOIClick}
        />
      </div>
    </div>
  );
}
```

---

## 🎨 Stratégie 5 : Images Optimisées

### Next.js Image Component

```typescript
import Image from 'next/image';

// ✅ Dans la liste
<Image
  src={poi.primary_photo?.variants?.card_sq?.cdn_url || '/placeholder.jpg'}
  alt={poi.name}
  width={96}
  height={96}
  className="object-cover rounded"
  loading="lazy"
  placeholder="blur"
  blurDataURL={poi.primary_photo?.blurhash || undefined}
/>
```

### Utiliser les variants Supabase

```typescript
// ✅ Liste : card_sq@1x (plus petite, plus rapide)
const listImageUrl = poi.primary_photo?.variants?.card_sq?.cdn_url;

// ✅ Detail page : card_sq@2x (haute qualité)
const detailImageUrl = poi.primary_photo?.variants?.['card_sq@2x']?.cdn_url;

// ✅ Fallback
const imageUrl = listImageUrl || detailImageUrl || '/placeholder.jpg';
```

---

## 🔄 Stratégie 6 : Prefetching Intelligent

### Précharger les bboxs adjacents

```typescript
// hooks/usePOIs.ts avec prefetch
import { useEffect } from 'react';
import { mutate } from 'swr';

export function usePOIs(params: POIsParams) {
  const { data, error, isLoading } = useSWR(/* ... */);

  // ✅ Précharger les bboxs adjacents
  useEffect(() => {
    if (!params.bbox) return;

    const [lngMin, latMin, lngMax, latMax] = params.bbox.split(',').map(Number);
    const lngDelta = lngMax - lngMin;
    const latDelta = latMax - latMin;

    // Précharger les 4 bboxs adjacents (nord, sud, est, ouest)
    const adjacentBboxes = [
      // Nord
      `${lngMin},${latMax},${lngMax},${latMax + latDelta}`,
      // Sud
      `${lngMin},${latMin - latDelta},${lngMax},${latMin}`,
      // Est
      `${lngMax},${latMin},${lngMax + lngDelta},${latMax}`,
      // Ouest
      `${lngMin - lngDelta},${latMin},${lngMin},${latMax}`,
    ];

    // Précharger après 1 seconde (pas de rush)
    const timeout = setTimeout(() => {
      adjacentBboxes.forEach(bbox => {
        mutate(
          `/v1/pois?bbox=${bbox}&city=${params.city}`,
          undefined,
          { revalidate: true }
        );
      });
    }, 1000);

    return () => clearTimeout(timeout);
  }, [params.bbox]);

  return { data, error, isLoading };
}
```

**Gain** :
- ✅ Si l'utilisateur bouge la map → bbox déjà en cache
- ✅ Impression de rapidité instantanée

---

## 📦 Stratégie 7 : Bundle Optimization

### Next.js App Router

```typescript
// app/layout.tsx
import { Inter } from 'next/font/google';

const inter = Inter({
  subsets: ['latin'],
  display: 'swap', // ✅ Évite le flash de texte
});

export default function RootLayout({ children }) {
  return (
    <html lang="fr">
      <body className={inter.className}>
        {children}
      </body>
    </html>
  );
}

// app/page.tsx
import dynamic from 'next/dynamic';

// ✅ Lazy load la map (client component lourd)
const MapAndList = dynamic(
  () => import('@/components/MapAndList').then(mod => mod.MapAndList),
  {
    ssr: false, // Pas de SSR pour la map
    loading: () => <MapSkeleton />
  }
);

export default function HomePage() {
  return <MapAndList />;
}
```

### Webpack Bundle Analyzer

```bash
npm install -D @next/bundle-analyzer
```

```javascript
// next.config.js
const withBundleAnalyzer = require('@next/bundle-analyzer')({
  enabled: process.env.ANALYZE === 'true',
});

module.exports = withBundleAnalyzer({
  // ... config
});
```

```bash
# Analyser le bundle
ANALYZE=true npm run build
```

---

## 🎯 Stratégie 8 : Debouncing & Throttling

### Debounce custom hook

```typescript
// hooks/useDebounce.ts
import { useEffect, useState } from 'react';

export function useDebounce<T>(value: T, delay: number = 300): T {
  const [debouncedValue, setDebouncedValue] = useState<T>(value);

  useEffect(() => {
    const handler = setTimeout(() => {
      setDebouncedValue(value);
    }, delay);

    return () => clearTimeout(handler);
  }, [value, delay]);

  return debouncedValue;
}

// Utilisation
const [searchQuery, setSearchQuery] = useState('');
const debouncedSearch = useDebounce(searchQuery, 500);

useEffect(() => {
  // API call avec debouncedSearch
}, [debouncedSearch]);
```

---

## 📊 Performances Attendues

### Timeline optimale

```
User déplace la map
    ↓
0ms     : Debounce start
    ↓
300ms   : Calculate bbox, check SWR cache
    ↓
300ms   : Cache HIT → Update UI immédiatement ✅
OU
300-330ms : Cache MISS API HIT → 30ms pour réponse ✅
OU
300-430ms : Cache MISS API MISS → 130ms pour réponse ⚠️

Total perçu par l'utilisateur :
- Best case: 300ms (debounce + cache client)
- Good case: 330ms (debounce + cache API)
- Worst case: 430ms (debounce + full API call)
```

---

## 🏆 Checklist Finale

### Must-have (Priorité 1)
- [ ] SWR ou React Query pour cache client
- [ ] Debounce 300ms sur map moveend
- [ ] Virtualisation de la liste (react-window)
- [ ] Images lazy loading
- [ ] API key dans headers

### Nice-to-have (Priorité 2)
- [ ] Prefetching des bboxs adjacents
- [ ] Image optimization (Next.js Image)
- [ ] Bundle splitting (dynamic import)
- [ ] Skeleton loading states

### Advanced (Priorité 3)
- [ ] Service Worker pour cache offline
- [ ] WebSocket pour updates temps réel
- [ ] Clustering des markers (> 100 POIs)
- [ ] Infinite scroll sur la liste

---

## 🧪 Comment Tester les Performances

### Chrome DevTools

```javascript
// Mesurer le temps de render
performance.mark('map-start');
// ... render map
performance.mark('map-end');
performance.measure('map-render', 'map-start', 'map-end');

// Voir les résultats
performance.getEntriesByType('measure').forEach(entry => {
  console.log(`${entry.name}: ${entry.duration}ms`);
});
```

### React DevTools Profiler

1. Installer React DevTools extension
2. Onglet "Profiler"
3. Start recording
4. Déplacer la map
5. Stop recording
6. Analyser les composants lents

### Lighthouse CI

```bash
npm install -g @lhci/cli

# Run audit
lhci autorun --config=lighthouserc.js
```

---

## 📈 Métriques Cibles

| Métrique | Cible | Actuel (estimé) |
|----------|-------|-----------------|
| **First Contentful Paint** | < 1.8s | ? |
| **Largest Contentful Paint** | < 2.5s | ? |
| **Time to Interactive** | < 3.8s | ? |
| **Map moveend → Update UI** | < 500ms | 300-430ms ✅ |
| **Scroll FPS** | 60 FPS | 60 FPS ✅ |
| **Bundle size (JS)** | < 200KB | ? |

---

## 🔗 Ressources

- [Next.js Performance](https://nextjs.org/docs/app/building-your-application/optimizing)
- [SWR Documentation](https://swr.vercel.app/)
- [React Query](https://tanstack.com/query/latest)
- [React Window](https://react-window.vercel.app/)
- [Mapbox GL JS](https://docs.mapbox.com/mapbox-gl-js/)
- [Web Vitals](https://web.dev/vitals/)

---

## 💡 Tips Finaux

1. **Prioriser le cache client** → SWR/React Query (gain le plus important)
2. **Débouncer les movements map** → 300ms optimal
3. **Virtualiser la liste** → react-window (60 FPS garanti)
4. **Lazy load tout ce qui est lourd** → dynamic import
5. **Monitorer avec Chrome DevTools** → identifier les bottlenecks

**Avec ces optimisations, tu auras une expérience aussi fluide qu'Airbnb** 🚀
