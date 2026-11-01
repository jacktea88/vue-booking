<script setup lang="ts">
const props = defineProps<{ modelValue: number; min?: number; max: number; label: string }>()
const emit = defineEmits<{ 'update:modelValue': [number] }>()
function step(d: number) {
  const next = Math.min(props.max, Math.max(props.min ?? 1, props.modelValue + d))
  emit('update:modelValue', next)
}
</script>

<template>
  <div>
    <span class="form-label">{{ label }}</span>
    <div class="d-inline-flex align-items-center gap-3 rounded-3 border bg-white px-2 py-1">
      <button type="button" class="btn btn-link text-body text-decoration-none fs-5 fw-bold lh-1 px-2"
              :aria-label="`-1`" :disabled="modelValue <= (min ?? 1)" @click="step(-1)">−</button>
      <span class="fw-semibold small tabular-nums text-center" style="min-width: 1.5rem">{{ modelValue }}</span>
      <button type="button" class="btn btn-link text-body text-decoration-none fs-5 fw-bold lh-1 px-2"
              :aria-label="`+1`" :disabled="modelValue >= max" @click="step(1)">+</button>
    </div>
  </div>
</template>
