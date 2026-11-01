<script setup lang="ts">
const props = defineProps<{ status: string; label: string }>()
const tones: Record<string, string> = {
  confirmed: 'bg-success-subtle text-success-emphasis', paid: 'bg-success-subtle text-success-emphasis',
  verified: 'bg-success-subtle text-success-emphasis', published: 'bg-success-subtle text-success-emphasis',
  approved: 'bg-success-subtle text-success-emphasis', completed: 'bg-secondary-subtle text-secondary-emphasis',
  pending: 'bg-warning-subtle text-warning-emphasis', requires_payment: 'bg-warning-subtle text-warning-emphasis',
  authorized: 'bg-info-subtle text-info-emphasis', in_progress: 'bg-info-subtle text-info-emphasis', boarding: 'bg-info-subtle text-info-emphasis',
  open: 'bg-info-subtle text-info-emphasis', draft: 'bg-light text-secondary',
  rejected: 'bg-danger-subtle text-danger-emphasis', cancelled: 'bg-danger-subtle text-danger-emphasis', failed: 'bg-danger-subtle text-danger-emphasis',
  no_show: 'bg-danger-subtle text-danger-emphasis', expired: 'bg-danger-subtle text-danger-emphasis',
  refunded: 'bg-violet-subtle text-violet-emphasis', partially_refunded: 'bg-violet-subtle text-violet-emphasis',
  closed: 'bg-secondary-subtle text-secondary-emphasis',
}
const tone = tones[props.status] ?? 'bg-secondary-subtle text-secondary-emphasis'
</script>

<template><span class="badge rounded-pill fw-medium" :class="tone">{{ label }}</span></template>
