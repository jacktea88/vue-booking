<script setup lang="ts">
const props = defineProps<{ status: string; label: string }>()
const tones: Record<string, string> = {
  confirmed: 'bg-emerald-100 text-emerald-800', paid: 'bg-emerald-100 text-emerald-800',
  verified: 'bg-emerald-100 text-emerald-800', published: 'bg-emerald-100 text-emerald-800',
  approved: 'bg-emerald-100 text-emerald-800', completed: 'bg-slate-200 text-slate-700',
  pending: 'bg-amber-100 text-amber-800', requires_payment: 'bg-amber-100 text-amber-800',
  authorized: 'bg-sky-100 text-sky-800', in_progress: 'bg-sky-100 text-sky-800', boarding: 'bg-sky-100 text-sky-800',
  open: 'bg-sky-100 text-sky-800', draft: 'bg-slate-100 text-slate-600',
  rejected: 'bg-red-100 text-red-800', cancelled: 'bg-red-100 text-red-800', failed: 'bg-red-100 text-red-800',
  no_show: 'bg-red-100 text-red-800', expired: 'bg-red-100 text-red-800',
  refunded: 'bg-violet-100 text-violet-800', partially_refunded: 'bg-violet-100 text-violet-800',
  closed: 'bg-slate-200 text-slate-700',
}
const tone = tones[props.status] ?? 'bg-slate-100 text-slate-700'
</script>

<template><span class="badge" :class="tone">{{ label }}</span></template>
