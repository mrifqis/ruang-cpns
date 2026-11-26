<script setup>
const props = defineProps({
  db: Object,
  user: Object,
  admin: Boolean,
  tipId: { type: String, default: '' }
})
const emit = defineEmits(['login', 'catalog'])
const stages = ['Administrasi', 'SKD', 'SKB', 'Pemberkasan', 'Lainnya']
const statuses = { pending: 'Menunggu tinjauan', published: 'Tayang', rejected: 'Ditolak', archived: 'Diarsipkan' }
const columns = 'id,title,stage,body,selection_year,source_url,status,created_at'
const stage = ref('')
const tips = ref([])
const counts = ref({})
const reports = ref([])
const log = ref([])
const loading = ref(false)
const loadError = ref('')
const busy = ref(false)
const mode = ref('')
const moderating = ref(false)
const notice = ref('')
const error = ref('')
const target = ref(null)
const blank = () => ({ title: '', stage: '', body: '', selection_year: '', source_url: '', status: 'pending', note: '' })
const form = reactive(blank())
const bodyLength = computed(() => [...form.body.trim()].length)
const bodyLengthMessage = 'Isi tips harus 20–5.000 karakter setelah spasi dan baris kosong di awal dan akhir diabaikan.'
let revision = 0

const published = computed(() => tips.value.filter(tip => tip.status === 'published'))
const filtered = computed(() => published.value.filter(tip => !stage.value || tip.stage === stage.value))
const selected = computed(() => published.value.find(tip => tip.id === props.tipId))
const myPending = computed(() => props.user && !props.admin ? tips.value.filter(tip => tip.status !== 'published') : [])
const titleFor = id => tips.value.find(tip => tip.id === id)?.title ?? 'Tips'
const summarize = body => body.length > 180 ? body.slice(0, 180).trimEnd() + '…' : body

function data(result) {
  if (result.error) throw result.error
  return result.data
}

function message(problem) {
  if (problem.code === '23514' && problem.message?.includes('tips_body_check')) return bodyLengthMessage
  if (['PGRST202','PGRST205','42P01','42883'].includes(problem.code)) return 'Fitur tips belum tersedia. Hubungi pengelola portal.'
  if (problem.code === '23505') return 'Tanggapan Anda untuk tips ini sudah tercatat.'
  return problem.message || 'Terjadi kesalahan.'
}

async function load() {
  if (!props.db) return
  const request = ++revision
  loading.value = true
  loadError.value = ''
  try {
    const [entries, totals, complaints, actions] = await Promise.all([
      props.db.from('tips').select(columns).order('created_at', { ascending: false }),
      props.db.rpc('tip_helpful_counts'),
      props.admin ? props.db.from('tip_feedback').select('id,tip_id,reason').eq('kind','report').is('resolved_at', null).order('created_at') : { data: [] },
      props.admin ? props.db.from('tip_moderation').select('id,tip_id,action,note').order('created_at', { ascending: false }).limit(30) : { data: [] }
    ])
    if (request !== revision) return
    const nextTips = data(entries)
    const nextCounts = Object.fromEntries(data(totals).map(row => [row.tip_id, row.total]))
    reports.value = data(complaints)
    log.value = data(actions)
    tips.value = nextTips
    counts.value = nextCounts
  } catch (problem) {
    if (request === revision) loadError.value = message(problem)
  } finally {
    if (request === revision) loading.value = false
  }
}

watch([() => props.user?.id, () => props.admin], () => {
  tips.value = []
  reports.value = []
  log.value = []
  if (!props.admin) {
    moderating.value = false
    if (['edit', 'resolve'].includes(mode.value)) mode.value = ''
  }
  load()
}, { immediate: true })

watch(() => props.tipId, () => {
  moderating.value = false
  mode.value = ''
  notice.value = ''
  error.value = ''
})

function start(kind, item = null) {
  if (!props.db) {
    notice.value = 'Hubungkan Supabase untuk menggunakan fitur kontribusi.'
    return
  }
  if (!props.user) return emit('login')
  target.value = item
  Object.assign(form, blank(), kind === 'edit' ? item : {})
  notice.value = ''
  error.value = ''
  mode.value = kind
  nextTick(() => document.getElementById('tip-form')?.focus())
}

async function save(operation, success) {
  if (busy.value) return
  busy.value = true
  notice.value = ''
  error.value = ''
  try {
    data(await operation())
    mode.value = ''
    notice.value = success
    await load()
  } catch (problem) {
    error.value = message(problem)
  } finally {
    busy.value = false
  }
}

function safeUrl(value) {
  if (!value?.trim()) return null
  const url = new URL(value.trim())
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) {
    throw new Error('Masukkan tautan sumber HTTP atau HTTPS.')
  }
  return url.href
}

function values() {
  if (bodyLength.value < 20 || bodyLength.value > 5000) throw new Error(bodyLengthMessage)
  return {
    title: form.title.trim(), stage: form.stage, body: form.body.trim(),
    selection_year: form.selection_year || null, source_url: safeUrl(form.source_url)
  }
}

function feedback(tip, kind, reason = null) {
  if (!props.user) return emit('login')
  return save(
    () => props.db.from('tip_feedback').insert({ tip_id: tip.id, kind, reason }),
    kind === 'helpful' ? 'Terima kasih. Tanda Membantu tersimpan.' : 'Laporan dikirim ke admin.'
  )
}

function submit() {
  if (mode.value === 'report') return feedback(target.value, 'report', form.note.trim())
  if (mode.value === 'resolve') return save(
    () => props.db.rpc('resolve_tip_report', { target: target.value.id, note: form.note.trim() }),
    'Laporan ditutup.'
  )
  if (mode.value === 'edit') return save(() => {
    const entry = values()
    return props.db.rpc('moderate_tip', {
      target: target.value.id, expected_status: target.value.status,
      new_title: entry.title, new_stage: entry.stage, new_body: entry.body,
      new_year: entry.selection_year, new_source: entry.source_url, new_status: form.status, note: form.note.trim()
    })
  }, 'Perubahan tips tersimpan.')
  return save(() => props.db.from('tips').insert(values()), 'Tips dikirim dan menunggu tinjauan admin.')
}

function toggleModeration() {
  moderating.value = !moderating.value
  mode.value = ''
  error.value = ''
  notice.value = ''
}
</script>

<template>
  <main class="wrap directory tips-portal">
    <div class="section-head tip-heading">
      <div>
        <h1 class="admin-title">Tips &amp; Pengalaman</h1>
        <p>Saran dari pelamar untuk membantu Anda mempersiapkan seleksi CPNS.</p>
      </div>
      <div class="actions">
        <button v-if="admin" class="quiet" @click="toggleModeration">{{ moderating ? 'Lihat daftar tips' : 'Moderasi tips' }}</button>
        <button v-if="!moderating" class="primary" @click="start('new')">Tulis tips</button>
      </div>
    </div>

    <p v-if="notice" class="callout" role="status">{{ notice }}</p>
    <p v-if="error && !mode" class="error" role="alert">{{ error }}</p>
    <p v-if="loadError" class="callout" role="alert">{{ loadError }}</p>

    <form v-if="mode" id="tip-form" class="panel tip-form" tabindex="-1" @submit.prevent="submit">
      <div class="section-head">
        <h2>{{ { new: 'Tulis tips', edit: 'Sunting tips', report: 'Laporkan tips', resolve: 'Tutup laporan' }[mode] }}</h2>
        <button type="button" class="quiet" :disabled="busy" @click="mode=''; error=''">Batal</button>
      </div>
      <template v-if="mode==='new' || mode==='edit'">
        <label>Judul<input v-model.trim="form.title" required minlength="5" maxlength="120"></label>
        <div class="form-grid">
          <label>Tahapan<select v-model="form.stage" required><option value="" disabled>Pilih tahapan</option><option v-for="item in stages" :key="item">{{ item }}</option></select></label>
          <label>Tahun seleksi (opsional)<input v-model.number="form.selection_year" type="number" min="2000" max="2100" step="1"></label>
        </div>
        <label>Isi tips<textarea v-model="form.body" required rows="6" aria-describedby="tip-body-length" placeholder="Ceritakan apa yang Anda lakukan dan apa yang membantu."></textarea><small id="tip-body-length">{{ bodyLength }} karakter · Minimal 20, maksimal 5.000</small></label>
        <label>Tautan sumber (opsional)<input v-model.trim="form.source_url" type="url" maxlength="2048" placeholder="https://"></label>
      </template>
      <template v-if="mode==='edit'">
        <label>Status<select v-model="form.status"><option v-for="(name,key) in statuses" :key="key" :value="key">{{ name }}</option></select></label>
      </template>
      <p v-if="mode==='report'">Jelaskan bagian yang perlu ditinjau, misalnya informasi usang, keliru, atau memuat data pribadi.</p>
      <p v-if="mode==='resolve'">{{ target.reason }}</p>
      <label v-if="mode!=='new'">{{ mode==='resolve' ? 'Hasil peninjauan' : 'Alasan' }}<textarea v-model.trim="form.note" required :minlength="mode==='report' ? 5 : 2" maxlength="500"></textarea></label>
      <p v-if="error" class="error" role="alert">{{ error }}</p>
      <button class="primary" type="submit" :disabled="busy">{{ busy ? 'Memproses…' : mode==='new' ? 'Kirim untuk ditinjau' : mode==='report' ? 'Kirim laporan' : 'Simpan' }}</button>
    </form>

    <template v-if="moderating && admin">
      <section class="panel">
        <h2>Kiriman tips</h2>
        <p v-if="!tips.length && !loading && !loadError">Belum ada kiriman.</p>
        <div v-for="tip in [...tips].sort((a,b) => Number(b.status==='pending') - Number(a.status==='pending'))" :key="tip.id" class="row">
          <div><strong>{{ tip.title }}</strong><p>{{ tip.stage }} · {{ statuses[tip.status] }}</p></div>
          <button class="quiet" @click="start('edit',tip)">Tinjau</button>
        </div>
      </section>
      <section class="panel">
        <h2>Laporan tips</h2>
        <p v-if="!reports.length && !loadError">Belum ada laporan terbuka.</p>
        <div v-for="report in reports" :key="report.id" class="row">
          <div><strong>{{ titleFor(report.tip_id) }}</strong><p>{{ report.reason }}</p></div>
          <div class="actions">
            <button v-if="tips.some(tip=>tip.id===report.tip_id)" class="quiet" @click="start('edit',tips.find(tip=>tip.id===report.tip_id))">Tinjau tips</button>
            <button class="quiet" @click="start('resolve',report)">Tutup laporan</button>
          </div>
        </div>
      </section>
      <section v-if="log.length" class="panel">
        <h2>Riwayat moderasi tips</h2>
        <div v-for="entry in log" :key="entry.id" class="row">
          <div><strong>{{ titleFor(entry.tip_id) }}</strong><p>{{ statuses[entry.action] || 'Laporan ditutup' }} · {{ entry.note }}</p></div>
        </div>
      </section>
    </template>

    <template v-else-if="tipId">
      <a href="#tips" class="quiet">Kembali ke daftar tips</a>
      <article v-if="selected" class="panel tip-detail">
        <div class="labels"><span>Pengalaman pelamar</span><span>{{ selected.stage }}</span><span v-if="selected.selection_year">Seleksi {{ selected.selection_year }}</span></div>
        <h2>{{ selected.title }}</h2>
        <p class="tip-body">{{ selected.body }}</p>
        <a v-if="selected.source_url" class="quiet" :href="selected.source_url" target="_blank" rel="noopener noreferrer">Buka sumber</a>
        <div class="card-actions">
          <button class="quiet" :disabled="busy" @click="feedback(selected,'helpful')">Membantu ({{ counts[selected.id] ?? 0 }})</button>
          <button class="quiet" @click="start('report',selected)">Laporkan</button>
          <button v-if="['SKD', 'SKB'].includes(selected.stage)" class="quiet" @click="emit('catalog', 'Latihan & tryout')">Lihat latihan &amp; tryout</button>
        </div>
      </article>
      <p v-else-if="!loading && !loadError" class="empty">Tips ini tidak ditemukan atau sedang tidak tayang.</p>
    </template>

    <template v-else>
      <div class="filters" aria-label="Filter tahapan">
        <button v-for="item in ['', ...stages]" :key="item" :aria-pressed="stage===item" @click="stage=item">{{ item || 'Semua tahapan' }}</button>
      </div>
      <p v-if="!filtered.length && !loading && !loadError" class="empty">Belum ada tips yang tayang untuk pilihan ini.</p>
      <div class="cards">
        <article v-for="tip in filtered" :key="tip.id" class="card">
          <div class="labels"><span>{{ tip.stage }}</span><span v-if="tip.selection_year">Seleksi {{ tip.selection_year }}</span></div>
          <h2 class="tip-card-title">{{ tip.title }}</h2>
          <p>{{ summarize(tip.body) }}</p>
          <div class="card-actions"><a class="primary" :href="'#tips/'+tip.id">Baca tips</a></div>
        </article>
      </div>
      <section v-if="myPending.length" class="panel">
        <h2>Tips saya</h2>
        <div v-for="tip in myPending" :key="tip.id" class="row"><strong>{{ tip.title }}</strong><span>{{ statuses[tip.status] }}</span></div>
      </section>
    </template>
    <p v-if="loading" role="status">Memuat tips…</p>
  </main>
</template>

<style scoped>
.tip-heading { flex-wrap: wrap; }
.tip-heading .admin-title { margin-top: 0; }
.tip-form { display: grid; gap: .8rem; margin-bottom: 1rem; }
.tip-form label { display: grid; gap: .25rem; font-weight: 650; }
.tip-form input { width: 100%; border: 1px solid #aebfb2; border-radius: 8px; padding: .55rem .7rem; }
.tip-form > .primary { justify-self: start; }
.tip-detail { max-width: 760px; }
.tip-detail h2 { margin-block: .65rem; font-size: clamp(1.5rem, 3vw, 2.15rem); }
.tip-body { white-space: pre-wrap; overflow-wrap: anywhere; line-height: 1.7; margin-bottom: 1rem; }
.tip-card-title { font-size: 1.24rem; overflow-wrap: anywhere; }
.row p { overflow-wrap: anywhere; }
</style>
