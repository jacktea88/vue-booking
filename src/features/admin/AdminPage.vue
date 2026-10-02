<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import DataTable from '@/components/DataTable.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import { adminService, profileService } from '@/services/domain'
import { useToast } from '@/composables/useToast'
import { formatDateTime, formatDzd } from '@/utils/format'
import { PAGE_SIZE } from '@/utils/constants'
import { toAppError } from '@/types/errors'
import type { AdminStats, DocumentStatus, Setting, UserRole } from '@/types'

const { t, locale } = useI18n()
const toast = useToast()

type Section = 'dashboard' | 'users' | 'verification' | 'vehicles' | 'trips' | 'bookings'
  | 'payments' | 'resales' | 'transfers' | 'ratings' | 'settings' | 'audit'

const sections: Section[] = ['dashboard', 'users', 'verification', 'vehicles', 'trips', 'bookings',
  'payments', 'resales', 'transfers', 'ratings', 'settings', 'audit']
const sectionLabel: Record<Section, string> = {
  dashboard: 'admin.dashboard', users: 'admin.users', verification: 'admin.verification', vehicles: 'admin.vehicles',
  trips: 'admin.trips', bookings: 'admin.bookings', payments: 'admin.payments', resales: 'admin.resales',
  transfers: 'admin.transfers', ratings: 'admin.ratings', settings: 'admin.settings', audit: 'admin.audit',
}

const active = ref<Section>('dashboard')
const page = ref(0)
const search = ref('')
const rows = ref<any[]>([])
const total = ref(0)
const loading = ref(false)
const stats = ref<AdminStats | null>(null)
const settings = ref<Setting[]>([])
const rejectReason = ref<Record<string, string>>({})

const columns = computed<Array<{ key: string; label: string }>>(() => {
  switch (active.value) {
    case 'users': return [
      { key: 'full_name', label: t('auth.fullName') }, { key: 'role', label: t('admin.role') },
      { key: 'identity_status', label: t('profile.identity') }, { key: 'created_at', label: t('common.date') },
      { key: 'actions', label: t('common.actions') }]
    case 'verification': return [
      { key: 'type', label: t('profile.documents') }, { key: 'status', label: t('common.status') },
      { key: 'created_at', label: t('common.date') }, { key: 'actions', label: t('common.actions') }]
    case 'vehicles': return [
      { key: 'brand', label: t('profile.brand') }, { key: 'model', label: t('profile.model') },
      { key: 'plate_number', label: t('profile.plate') }, { key: 'capacity', label: t('profile.capacity') }]
    case 'trips': return [
      { key: 'departure_at', label: t('search.departure') }, { key: 'status', label: t('common.status') },
      { key: 'booking_mode', label: t('trip.mode') }]
    case 'bookings': return [
      { key: 'seats', label: t('common.seats') }, { key: 'total_amount', label: t('common.total') },
      { key: 'status', label: t('common.status') }, { key: 'source', label: t('booking.title') },
      { key: 'created_at', label: t('common.date') }]
    case 'payments': return [
      { key: 'amount', label: t('common.total') }, { key: 'status', label: t('common.status') },
      { key: 'refunded_amount', label: t('payment.status.refunded') }, { key: 'provider', label: t('payment.title') },
      { key: 'created_at', label: t('common.date') }]
    case 'resales': return [
      { key: 'seats_for_sale', label: t('resale.seatsForSale') }, { key: 'seats_sold', label: t('resale.sold', { sold: '', total: '' }) },
      { key: 'price_per_seat', label: t('common.price') }, { key: 'status', label: t('common.status') }]
    case 'transfers': return [
      { key: 'booking_id', label: t('booking.title') }, { key: 'status', label: t('common.status') },
      { key: 'created_at', label: t('common.date') }]
    case 'ratings': return [
      { key: 'rating', label: t('rating.title') }, { key: 'comment', label: t('rating.comment') },
      { key: 'created_at', label: t('common.date') }]
    case 'audit': return [
      { key: 'action', label: t('common.actions') }, { key: 'entity_type', label: t('common.details') },
      { key: 'entity_id', label: 'ID' }, { key: 'created_at', label: t('common.date') }]
    default: return []
  }
})

async function load() {
  loading.value = true
  const offset = page.value * PAGE_SIZE
  try {
    if (active.value === 'dashboard') { stats.value = await adminService.stats(); return }
    if (active.value === 'settings') { settings.value = await adminService.settings(); return }
    const map: Record<string, () => Promise<{ rows: any[]; count: number }>> = {
      users: () => adminService.users(PAGE_SIZE, offset, search.value),
      verification: () => adminService.documents('pending', PAGE_SIZE, offset),
      vehicles: () => adminService.vehicles(PAGE_SIZE, offset),
      trips: () => adminService.trips(PAGE_SIZE, offset),
      bookings: () => adminService.bookings(PAGE_SIZE, offset),
      payments: () => adminService.payments(PAGE_SIZE, offset),
      resales: () => adminService.resales(PAGE_SIZE, offset),
      transfers: () => adminService.transfers(PAGE_SIZE, offset),
      ratings: () => adminService.ratings(PAGE_SIZE, offset),
      audit: () => adminService.auditLogs(PAGE_SIZE, offset),
    }
    const res = await map[active.value]()
    rows.value = res.rows; total.value = res.count
  } catch (e) { toast.error(t(toAppError(e).i18nKey)) } finally { loading.value = false }
}

async function review(id: string, status: DocumentStatus) {
  try {
    await adminService.reviewDocument(id, status, rejectReason.value[id])
    toast.success(t('admin.updated')); await load()
  } catch (e) { toast.error(t(toAppError(e).i18nKey)) }
}

async function viewDocument(path: string) {
  const url = await profileService.signedDocumentUrl(path)
  if (url) window.open(url, '_blank', 'noopener')
}

async function setRole(userId: string, role: UserRole) {
  try { await adminService.setRole(userId, role); toast.success(t('admin.updated')); await load() }
  catch (e) { toast.error(t(toAppError(e).i18nKey)) }
}

async function saveSetting(s: Setting, raw: string) {
  try {
    await adminService.setSetting(s.key, JSON.parse(raw))
    toast.success(t('admin.updated')); await load()
  } catch (e) { toast.error(t(toAppError(e).i18nKey)) }
}

watch([active, page], load)
onMounted(load)
</script>

<template>
  <div class="lg:grid lg:grid-cols-[220px_1fr] lg:gap-6">
    <aside class="mb-4 lg:mb-0">
      <h1 class="mb-3 text-xl font-bold">{{ t('admin.title') }}</h1>
      <nav class="flex gap-2 overflow-x-auto pb-2 lg:flex-col lg:overflow-visible" :aria-label="t('admin.title')">
        <button v-for="s in sections" :key="s"
                class="whitespace-nowrap rounded-lg px-3 py-2 text-start text-sm font-medium"
                :class="active === s ? 'bg-brand-700 text-white' : 'bg-white text-slate-700 hover:bg-slate-100'"
                @click="active = s; page = 0">{{ t(sectionLabel[s]) }}</button>
      </nav>
    </aside>

    <main>
      <section v-if="active === 'dashboard'" class="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <div v-for="(label, key) in {
            pending_verifications: t('admin.pendingVerifications'), active_trips: t('admin.activeTrips'),
            upcoming_trips: t('admin.upcomingTrips'), bookings_today: t('admin.bookingsToday'),
            paid_amount_today: t('admin.paidToday'), refunded_amount_today: t('admin.refundedToday'),
            pending_transfers: t('admin.pendingTransfers'), open_resales: t('admin.openResales') }"
             :key="key" class="card">
          <p class="text-xs text-slate-500">{{ label }}</p>
          <p class="mt-1 text-xl font-bold text-brand-700">
            {{ key.includes('amount') ? formatDzd(Number(stats?.[key] ?? 0), locale) : (stats?.[key] ?? 0) }}
          </p>
        </div>
      </section>

      <section v-else-if="active === 'settings'" class="space-y-3">
        <div v-for="s in settings" :key="s.key" class="card flex flex-wrap items-end gap-3">
          <div class="flex-1">
            <label class="label" :for="`s-${s.key}`">{{ s.key }}</label>
            <input :id="`s-${s.key}`" class="field" :value="JSON.stringify(s.value)"
                   @keyup.enter="saveSetting(s, ($event.target as HTMLInputElement).value)" />
          </div>
          <span class="text-xs text-slate-400">{{ formatDateTime(s.updated_at, locale) }}</span>
        </div>
      </section>

      <section v-else>
        <div v-if="active === 'users'" class="mb-3">
          <input v-model="search" class="field max-w-xs" :placeholder="t('common.search')" @keyup.enter="page = 0; load()" />
        </div>
        <DataTable :columns="columns" :rows="rows" :page="page" :page-size="PAGE_SIZE" :total="total"
                   @update:page="page = $event">
          <template #cell-status="{ row }">
            <StatusBadge :status="row.status" :label="row.status" />
          </template>
          <template #cell-created_at="{ row }">{{ formatDateTime(row.created_at, locale) }}</template>
          <template #cell-departure_at="{ row }">{{ formatDateTime(row.departure_at, locale) }}</template>
          <template #cell-total_amount="{ row }">{{ formatDzd(row.total_amount, locale) }}</template>
          <template #cell-amount="{ row }">{{ formatDzd(row.amount, locale) }}</template>
          <template #cell-refunded_amount="{ row }">{{ formatDzd(row.refunded_amount, locale) }}</template>
          <template #cell-price_per_seat="{ row }">{{ formatDzd(row.price_per_seat, locale) }}</template>
          <template #cell-type="{ row }">{{ t(`profile.documentType.${row.type}`) }}</template>
          <template #cell-actions="{ row }">
            <div v-if="active === 'verification'" class="flex flex-wrap items-center gap-2">
              <button class="btn-ghost px-2 py-1 text-xs" @click="viewDocument(row.storage_path)">{{ t('admin.viewDocument') }}</button>
              <button class="btn-primary px-2 py-1 text-xs" @click="review(row.id, 'verified')">{{ t('common.approve') }}</button>
              <input v-model="rejectReason[row.id]" class="field max-w-[140px] py-1 text-xs" :placeholder="t('admin.rejectionReason')" />
              <button class="btn-danger px-2 py-1 text-xs" @click="review(row.id, 'rejected')">{{ t('common.reject') }}</button>
            </div>
            <select v-else-if="active === 'users'" class="field py-1 text-xs" :value="row.role"
                    @change="setRole(row.id, ($event.target as HTMLSelectElement).value as UserRole)">
              <option value="client">client</option><option value="driver">driver</option><option value="admin">admin</option>
            </select>
          </template>
        </DataTable>
      </section>
    </main>
  </div>
</template>
