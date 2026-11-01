<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { getMapProvider, type MapHandle } from '@/services/maps'
import type { GeoPoint } from '@/types'

const props = defineProps<{ center?: GeoPoint; markers?: Array<GeoPoint & { label?: string }>; height?: string }>()
const emit = defineEmits<{ pick: [GeoPoint] }>()

const el = ref<HTMLElement | null>(null)
let handle: MapHandle | null = null

onMounted(async () => {
  if (!el.value) return
  handle = await getMapProvider().renderMap(el.value, { center: props.center })
  handle.setMarkers(props.markers ?? [])
  handle.onClick((p) => emit('pick', p))
})

watch(() => props.markers, (m) => handle?.setMarkers(m ?? []), { deep: true })
onBeforeUnmount(() => handle?.destroy())
</script>

<template>
  <div ref="el" class="w-100 overflow-hidden rounded-3 bg-secondary-subtle" :style="{ height: height ?? '240px' }" aria-label="map" />
</template>
