<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import StatusBadge from '@/components/StatusBadge.vue'
import { profileService } from '@/services/domain'
import { useAuthStore } from '@/stores/auth'
import { useToast } from '@/composables/useToast'
import { toAppError } from '@/types/errors'
import { REQUIRED_CLIENT_DOCUMENTS, REQUIRED_DRIVER_DOCUMENTS } from '@/utils/constants'
import type { DocumentType, VerificationDocument, Vehicle } from '@/types'

const { t } = useI18n()
const auth = useAuthStore()
const toast = useToast()

const fullName = ref('')
const phone = ref('')
const documents = ref<VerificationDocument[]>([])
const vehicle = ref<Partial<Vehicle>>({ brand: '', model: '', color: '', plate_number: '', capacity: 4 })
const busy = ref(false)

const requiredDocs = computed<readonly DocumentType[]>(() =>
  auth.isDriver ? REQUIRED_DRIVER_DOCUMENTS : REQUIRED_CLIENT_DOCUMENTS)

function latest(type: DocumentType) {
  return documents.value.filter((d) => d.type === type)[0] ?? null
}

async function load() {
  if (!auth.user) return
  await auth.loadProfile()
  fullName.value = auth.profile?.full_name ?? ''
  phone.value = auth.profile?.phone ?? ''
  documents.value = await profileService.listDocuments(auth.user.id)
  if (auth.isDriver) {
    const v = await profileService.getVehicle(auth.user.id)
    if (v) vehicle.value = v
  }
}

async function saveProfile() {
  if (!auth.user) return
  busy.value = true
  try {
    await profileService.updateProfile(auth.user.id, { full_name: fullName.value, phone: phone.value })
    await auth.loadProfile()
    toast.success(t('profile.saved'))
  } catch (e) { toast.error(t(toAppError(e).i18nKey)) } finally { busy.value = false }
}

async function uploadDoc(type: DocumentType, e: Event) {
  const file = (e.target as HTMLInputElement).files?.[0]
  if (!file || !auth.user) return
  busy.value = true
  try {
    await profileService.submitDocument(auth.user.id, type, file)
    await load()
    toast.success(t('profile.saved'))
  } catch (err) { toast.error(t(toAppError(err).i18nKey)) } finally { busy.value = false }
}

async function saveVehicle() {
  if (!auth.user) return
  busy.value = true
  try {
    await profileService.upsertVehicle(auth.user.id, {
      brand: vehicle.value.brand!, model: vehicle.value.model!, color: vehicle.value.color!,
      plate_number: vehicle.value.plate_number!, capacity: Number(vehicle.value.capacity),
    })
    toast.success(t('profile.saved'))
  } catch (e) { toast.error(t(toAppError(e).i18nKey)) } finally { busy.value = false }
}

onMounted(load)
</script>

<template>
  <div class="space-y-4">
    <h1 class="text-xl font-bold">{{ t('profile.title') }}</h1>

    <section class="card">
      <h2 class="text-sm font-semibold text-slate-700">{{ t('profile.edit') }}</h2>
      <form class="mt-3 grid gap-3 sm:grid-cols-2" @submit.prevent="saveProfile">
        <div>
          <label class="label" for="fn">{{ t('auth.fullName') }}</label>
          <input id="fn" v-model="fullName" class="field" required />
        </div>
        <div>
          <label class="label" for="ph">{{ t('auth.phone') }}</label>
          <input id="ph" v-model="phone" class="field" type="tel" />
        </div>
        <div class="sm:col-span-2 flex items-center justify-between">
          <div class="text-sm text-slate-600">
            {{ t('profile.identity') }}:
            <StatusBadge v-if="auth.profile" :status="auth.profile.identity_status"
                         :label="t(`profile.identityStatus.${auth.profile.identity_status}`)" />
            <span v-if="auth.isDriver" class="ms-2">
              <StatusBadge :status="auth.isVerifiedDriver ? 'verified' : 'pending'"
                           :label="auth.isVerifiedDriver ? t('profile.driverVerified') : t('profile.identityStatus.pending')" />
            </span>
          </div>
          <button class="btn-primary" :disabled="busy" type="submit">{{ t('common.save') }}</button>
        </div>
      </form>
    </section>

    <section class="card">
      <h2 class="text-sm font-semibold text-slate-700">{{ t('profile.documents') }}</h2>
      <p v-if="auth.isDriver && !auth.isVerifiedDriver" class="mt-1 text-xs text-amber-700">{{ t('profile.driverNotVerified') }}</p>
      <ul class="mt-3 space-y-3">
        <li v-for="type in requiredDocs" :key="type" class="rounded-lg border border-slate-200 p-3">
          <div class="flex items-center justify-between gap-2">
            <span class="text-sm font-medium">{{ t(`profile.documentType.${type}`) }}</span>
            <StatusBadge v-if="latest(type)" :status="latest(type)!.status"
                         :label="t(`profile.documentStatus.${latest(type)!.status}`)" />
          </div>
          <p v-if="latest(type)?.rejection_reason" class="mt-1 text-xs text-red-600">{{ latest(type)!.rejection_reason }}</p>
          <input class="mt-2 block w-full text-xs" type="file" accept="image/*,.pdf"
                 :aria-label="t('profile.uploadDocument')" @change="uploadDoc(type, $event)" />
        </li>
      </ul>
    </section>

    <section v-if="auth.isDriver" class="card">
      <h2 class="text-sm font-semibold text-slate-700">{{ t('profile.vehicle') }}</h2>
      <form class="mt-3 grid gap-3 sm:grid-cols-2" @submit.prevent="saveVehicle">
        <div><label class="label" for="vb">{{ t('profile.brand') }}</label><input id="vb" v-model="vehicle.brand" class="field" required /></div>
        <div><label class="label" for="vm">{{ t('profile.model') }}</label><input id="vm" v-model="vehicle.model" class="field" required /></div>
        <div><label class="label" for="vc">{{ t('profile.color') }}</label><input id="vc" v-model="vehicle.color" class="field" required /></div>
        <div><label class="label" for="vp">{{ t('profile.plate') }}</label><input id="vp" v-model="vehicle.plate_number" class="field" required /></div>
        <div><label class="label" for="vk">{{ t('profile.capacity') }}</label>
          <input id="vk" v-model.number="vehicle.capacity" class="field" type="number" min="1" max="8" required /></div>
        <div class="flex items-end"><button class="btn-primary" :disabled="busy" type="submit">{{ t('profile.saveVehicle') }}</button></div>
      </form>
    </section>

    <button class="btn-secondary w-full sm:hidden" @click="auth.signOut()">{{ t('common.logout') }}</button>
  </div>
</template>
