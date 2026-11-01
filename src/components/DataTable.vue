<script setup lang="ts" generic="T extends Record<string, any>">
import { useI18n } from 'vue-i18n'
defineProps<{ columns: Array<{ key: string; label: string }>; rows: T[]; page: number; pageSize: number; total: number }>()
const emit = defineEmits<{ 'update:page': [number] }>()
const { t } = useI18n()
</script>

<template>
  <div>
    <div class="table-responsive">
      <table class="table table-sm table-bordered table-hover align-middle">
        <thead class="table-light">
          <tr><th v-for="c in columns" :key="c.key" scope="col">{{ c.label }}</th></tr>
        </thead>
        <tbody>
          <tr v-for="(row, i) in rows" :key="row.id ?? i">
            <td v-for="c in columns" :key="c.key">
              <slot :name="`cell-${c.key}`" :row="row">{{ row[c.key] ?? '—' }}</slot>
            </td>
          </tr>
          <tr v-if="!rows.length"><td :colspan="columns.length" class="py-4 text-center small text-secondary">{{ t('states.empty') }}</td></tr>
        </tbody>
      </table>
    </div>
    <div class="mt-3 d-flex align-items-center justify-content-between small text-secondary">
      <span>{{ t('common.page') }} {{ page + 1 }} {{ t('common.of') }} {{ Math.max(1, Math.ceil(total / pageSize)) }}</span>
      <div class="d-flex gap-2">
        <button class="btn btn-outline-secondary btn-sm" :disabled="page === 0" @click="emit('update:page', page - 1)">‹</button>
        <button class="btn btn-outline-secondary btn-sm" :disabled="(page + 1) * pageSize >= total" @click="emit('update:page', page + 1)">›</button>
      </div>
    </div>
  </div>
</template>
