<script setup lang="ts" generic="T extends Record<string, any>">
import { useI18n } from 'vue-i18n'
defineProps<{ columns: Array<{ key: string; label: string }>; rows: T[]; page: number; pageSize: number; total: number }>()
const emit = defineEmits<{ 'update:page': [number] }>()
const { t } = useI18n()
</script>

<template>
  <div>
    <div class="table-wrap">
      <table class="table">
        <thead>
          <tr><th v-for="c in columns" :key="c.key" scope="col">{{ c.label }}</th></tr>
        </thead>
        <tbody>
          <tr v-for="(row, i) in rows" :key="row.id ?? i" class="hover:bg-slate-50">
            <td v-for="c in columns" :key="c.key">
              <slot :name="`cell-${c.key}`" :row="row">{{ row[c.key] ?? '—' }}</slot>
            </td>
          </tr>
          <tr v-if="!rows.length"><td :colspan="columns.length" class="py-8 text-center text-sm text-slate-500">{{ t('states.empty') }}</td></tr>
        </tbody>
      </table>
    </div>
    <div class="mt-3 flex items-center justify-between text-sm text-slate-600">
      <span>{{ t('common.page') }} {{ page + 1 }} {{ t('common.of') }} {{ Math.max(1, Math.ceil(total / pageSize)) }}</span>
      <div class="flex gap-2">
        <button class="btn-secondary" :disabled="page === 0" @click="emit('update:page', page - 1)">‹</button>
        <button class="btn-secondary" :disabled="(page + 1) * pageSize >= total" @click="emit('update:page', page + 1)">›</button>
      </div>
    </div>
  </div>
</template>
