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
    <span class="label">{{ label }}</span>
    <div class="inline-flex items-center gap-3 rounded-lg border border-slate-300 bg-white px-2 py-1">
      <button type="button" class="h-8 w-8 rounded-md text-lg font-bold text-slate-700 hover:bg-slate-100"
              :aria-label="`-1`" :disabled="modelValue <= (min ?? 1)" @click="step(-1)">−</button>
      <span class="w-6 text-center text-sm font-semibold tabular-nums">{{ modelValue }}</span>
      <button type="button" class="h-8 w-8 rounded-md text-lg font-bold text-slate-700 hover:bg-slate-100"
              :aria-label="`+1`" :disabled="modelValue >= max" @click="step(1)">+</button>
    </div>
  </div>
</template>
