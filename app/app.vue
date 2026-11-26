<script setup>
import { createClient } from '@supabase/supabase-js'
const config = useRuntimeConfig().public
const db = config.supabaseUrl && config.supabaseKey ? createClient(config.supabaseUrl, config.supabaseKey) : null
const categories = ['Sumber resmi','Materi belajar','Latihan & tryout','Grup WA & Telegram','Pengalaman peserta']
const prices = ['Gratis','Berbayar','Campuran']
const statusNames = {pending:'Menunggu tinjauan', published:'Tayang', rejected:'Ditolak', archived:'Diarsipkan'}
const fields = 'id,title,url,category,price,description,status,official,reviewed_at,created_at'
const initialLinks = [
  {id:'sscasn',title:'SSCASN',url:'https://sscasn.bkn.go.id',category:categories[0],price:'Gratis',description:'Portal BKN untuk informasi dan pendaftaran seleksi calon aparatur sipil negara.',official:true,status:'published'},
  {id:'bkn',title:'Badan Kepegawaian Negara',url:'https://www.bkn.go.id',category:categories[0],price:'Gratis',description:'Baca pengumuman dan informasi kepegawaian dari BKN.',official:true,status:'published'}
]
const links = ref(db ? [] : initialLinks)
const checks = ref({})
const reports = ref([])
const history = ref([])
const user = ref(null)
const admin = ref(false)
const loading = ref(Boolean(db))
const busy = ref(false)
const view = ref('catalog')
const tipId = ref('')
function syncTipRoute() {
  const match = location.hash.match(/^#tips(?:\/([a-f0-9-]{36}))?$/i)
  tipId.value = match?.[1] || ''
  if (match) view.value = 'tips'
  else if (view.value === 'tips') view.value = 'catalog'
}
function navigate(nextView) {
  if (nextView === 'tips') location.hash = '#tips'
  else if (location.hash.startsWith('#tips')) window.history.pushState(null, '', location.pathname + location.search)
  view.value = nextView
}
const query = ref('')
const category = ref('')
const price = ref('')
const modal = ref('')
const email = ref('')
const note = ref('')
const selection = ref(null)
const resolution = ref(null)
const notice = ref({ message:'', error:false })
const blank = () => ({title:'',url:'',category:categories[1],price:prices[0],description:'',status:'pending',official:false})
const form = reactive(blank())
let subscription
let refreshVersion = 0
const catalog = computed(() => links.value.filter(link => link.status === 'published'))
const filtered = computed(() => catalog.value.filter(link =>
  (!category.value || link.category === category.value) &&
  (!price.value || link.price === price.value) &&
  [link.title,link.description,link.url,link.category].join(' ').toLowerCase().includes(query.value.trim().toLowerCase())
))
const queue = computed(() => links.value.filter(link => link.status !== 'published'))
const openReports = computed(() => reports.value.filter(item => !item.resolution))
function show(message, error = false) { notice.value = {message,error} }
function requireData(result) {
  if (result.error) throw result.error
  return result.data
}
function friendly(error) {
  if (error.code === '23505') return 'Tautan atau tanggapan ini sudah tercatat.'
  return error.message || 'Terjadi kesalahan.'
}
async function refresh() {
  const version = ++refreshVersion
  const role = user.value ? requireData(await db.rpc('is_admin')) : false
  const [entries, confirmations, complaints, log] = await Promise.all([
    db.from('links').select(fields).order('created_at',{ascending:false}),
    db.rpc('active_checks'),
    role ? db.from('feedback').select('id,link_id,kind,reason,resolution,created_at').eq('kind','report').order('created_at',{ascending:false}) : {data:[]},
    role ? db.from('moderation_log').select('id,link_id,action,note,created_at').order('created_at',{ascending:false}).limit(50) : {data:[]}
  ])
  if (version !== refreshVersion) return
  admin.value = role
  links.value = requireData(entries)
  checks.value = Object.fromEntries(requireData(confirmations).map(item => [item.link_id,item]))
  reports.value = requireData(complaints)
  history.value = requireData(log)
}
onMounted(() => {
  syncTipRoute()
  window.addEventListener('hashchange', syncTipRoute)
  if (!db) return
  subscription = db.auth.onAuthStateChange((_event, session) => {
    user.value = session?.user ?? null
    if (!user.value) { admin.value = false; if (view.value === 'admin') navigate('catalog') }
    setTimeout(async () => {
      try { await refresh() } catch (error) { show(friendly(error),true) }
      finally { loading.value = false }
    }, 0)
  }).data.subscription
})
onBeforeUnmount(() => {
  window.removeEventListener('hashchange', syncTipRoute)
  subscription?.unsubscribe()
})
async function action(operation, message, reload = true, close = true) {
  if (busy.value) return
  busy.value = true
  try {
    await operation()
    if (close) modal.value = ''
    show(message)
    if (reload) {
      try { await refresh() }
      catch (error) { show(message + ' Gagal memuat ulang: ' + friendly(error), true) }
    }
  } catch (error) { show(friendly(error),true) }
  finally { busy.value = false }
}
const date = value => value ? new Intl.DateTimeFormat('id-ID',{dateStyle:'medium',timeZone:'Asia/Makassar'}).format(new Date(value)) : ''
function domain(value) {
  try { return new URL(value).hostname } catch { return value }
}
const linkTitle = id => links.value.find(link => link.id === id)?.title || 'Tautan'
function open(kind, link = null) {
  if (!db) return show('Hubungkan Supabase untuk menggunakan fitur kontribusi.',true)
  notice.value = {message:'',error:false}
  selection.value = link
  note.value = ''
  if (kind === 'submit' || kind === 'edit') Object.assign(form, blank(), link ?? {})
  modal.value = user.value ? kind : 'login'
  nextTick(() => document.querySelector('.dialog input, .dialog textarea, .dialog button')?.focus())
}
function normalizedUrl(value) {
  const url = new URL(value.trim())
  if (!['https:','http:'].includes(url.protocol) || url.username || url.password) throw new Error('Masukkan URL HTTP atau HTTPS tanpa kredensial.')
  return url.href
}
function linkValues() {
  return {title:form.title.trim(),url:normalizedUrl(form.url),category:form.category,price:form.price,description:form.description.trim()}
}
function submit() {
  if (modal.value === 'login') return action(async () => {
    requireData(await db.auth.signInWithOtp({email:email.value.trim(),options:{emailRedirectTo:location.origin + '/'}}))
  },'Periksa email untuk membuka tautan masuk.',false)
  if (modal.value === 'report') return sendFeedback(selection.value,'report',note.value.trim())
  if (modal.value === 'resolve') return action(async () => {
    requireData(await db.rpc('resolve_report',{target:resolution.value.id,note:note.value.trim()}))
  },'Hasil peninjauan tersimpan.')
  if (modal.value === 'edit') return action(async () => {
    const values = linkValues()
    if (form.url === selection.value.url) values.url = selection.value.url
    requireData(await db.rpc('moderate_link',{
      target:selection.value.id,expected_url:selection.value.url,new_title:values.title,new_url:values.url,
      new_category:values.category,new_price:values.price,new_description:values.description,
      new_status:form.status,new_official:form.official,note:note.value.trim()
    }))
  },'Perubahan moderasi tersimpan.')
  return action(async () => {
    requireData(await db.from('links').insert(linkValues()))
  },'Usulan diterima dan menunggu tinjauan admin.')
}
function sendFeedback(link,kind,reason = null) {
  if (!user.value) return open('login')
  return action(async () => {
    requireData(await db.from('feedback').insert({link_id:link.id,kind,reason}))
  }, kind === 'active' ? 'Konfirmasi tautan tersimpan.' : 'Laporan dikirim ke admin.')
}
</script>

<template>
  <header class="site-header">
    <div class="wrap nav">
      <button class="brand" @click="navigate('catalog')"><span class="brand-mark">R</span> Ruang CPNS</button>
      <nav aria-label="Navigasi utama">
        <button class="quiet" :aria-current="view==='tips' ? 'page' : undefined" @click="navigate('tips')">Tips &amp; Pengalaman</button>
        <button v-if="admin" class="quiet" @click="navigate(view==='admin'?'catalog':'admin')">{{ view==='admin'?'Katalog':'Moderasi' }}</button>
        <button v-if="user" class="quiet" @click="action(async()=>requireData(await db.auth.signOut()),'Anda telah keluar.',false)">Keluar</button>
        <button v-else class="quiet" @click="open('login')">Masuk</button>
        <button class="primary" @click="open('submit')">＋ Usulkan tautan</button>
      </nav>
    </div>
  </header>

  <main v-if="view==='catalog'">
    <section class="hero">
      <div class="wrap hero-grid">
        <div>
          <p class="eyebrow">DIREKTORI SUMBER BELAJAR</p>
          <h1>Temukan bekal<br>seleksi <em>CPNS.</em></h1>
          <p class="intro">Satu tempat untuk mencari sumber resmi, materi belajar, latihan soal, dan komunitas persiapan CPNS.</p>
          <label class="search"><span aria-hidden="true">⌕</span><input v-model="query" type="search" placeholder="Cari materi, tryout, atau komunitas" aria-label="Cari tautan"></label>
        </div>
        <div class="hero-art" aria-hidden="true">
          <div class="art-sheet art-back"></div>
          <div class="art-sheet art-front"><span>RUANG CPNS</span><strong>Bekal<br>seleksi.</strong><i></i><i></i><i></i></div>
          <div class="art-check">✓</div>
        </div>
      </div>
    </section>

    <section class="wrap directory">
      <div v-if="!db" class="callout">Mode pratinjau. Katalog memakai dua contoh sumber resmi.</div>
      <div class="section-head"><div><h2>Katalog tautan</h2><p>{{ loading?'Memuat katalog…':filtered.length + ' tautan ditemukan' }}</p></div>
        <select v-model="price" aria-label="Filter biaya"><option value="">Semua biaya</option><option v-for="item in prices" :key="item">{{ item }}</option></select>
      </div>
      <div class="filters" aria-label="Filter kategori">
        <button v-for="item in ['',...categories]" :key="item" :aria-pressed="category===item" @click="category=item">{{ item || 'Semua kategori' }}</button>
      </div>
      <div v-if="!loading && !filtered.length" class="empty">Belum ada tautan yang cocok dengan pencarian ini.</div>
      <div class="cards">
        <article v-for="link in filtered" :key="link.id" class="card">
          <div class="card-top"><span class="icon" aria-hidden="true">{{ link.official?'✓':'↗' }}</span><span class="pill">{{ link.price }}</span></div>
          <div class="labels"><span>{{ link.official?'Sumber resmi':link.category }}</span><span v-if="link.reviewed_at">Ditinjau admin</span></div>
          <h3>{{ link.title }}</h3>
          <p>{{ link.description }}</p>
          <small>{{ domain(link.url) }}</small>
          <small v-if="checks[link.id]">{{ checks[link.id].confirmations }} konfirmasi aktif · {{ date(checks[link.id].last_checked) }}</small>
          <div class="card-actions"><a class="primary" :href="link.url" target="_blank" rel="noopener noreferrer">Buka tautan</a><button class="quiet" @click="sendFeedback(link,'active')">Masih aktif</button><button class="quiet" @click="open('report',link)">Laporkan</button></div>
        </article>
      </div>
      <section v-if="user && !admin && queue.length" class="panel">
        <h2>Usulan saya</h2><div v-for="link in queue" :key="link.id" class="row"><strong>{{ link.title }}</strong><span>{{ statusNames[link.status] }}</span></div>
      </section>
    </section>
  </main>

  <TipsPortal v-else-if="view==='tips'" :db="db" :user="user" :admin="admin" :tip-id="tipId" @login="open('login')" @catalog="category=$event; query=''; price=''; navigate('catalog')" />

  <main v-else-if="admin" class="wrap directory">
    <h1 class="admin-title">Moderasi tautan</h1>
    <section class="panel">
      <h2>Laporan terbuka</h2>
      <p v-if="!openReports.length">Belum ada laporan terbuka.</p>
      <div v-for="item in openReports" :key="item.id" class="row">
        <div><strong>{{ linkTitle(item.link_id) }}</strong><p>{{ item.reason }}</p><small>{{ date(item.created_at) }}</small></div>
        <div class="actions">
          <button v-if="links.some(link=>link.id===item.link_id)" class="quiet" @click="open('edit',links.find(link=>link.id===item.link_id))">Tinjau tautan</button>
          <button class="quiet" @click="resolution=item;open('resolve')">Tutup laporan</button>
        </div>
      </div>
    </section>
    <section class="panel">
      <h2>Semua tautan</h2>
      <div v-for="link in [...queue,...catalog]" :key="link.id" class="row">
        <div><strong>{{ link.title }}</strong><p>{{ statusNames[link.status] }} · {{ domain(link.url) }}</p></div>
        <button class="quiet" @click="open('edit',link)">Sunting</button>
      </div>
    </section>
    <section class="panel">
      <h2>Riwayat moderasi</h2>
      <p v-if="!history.length">Belum ada tindakan moderasi.</p>
      <div v-for="item in history" :key="item.id" class="row"><div><strong>{{ linkTitle(item.link_id) }}</strong><p>{{ statusNames[item.action] || 'Laporan ditutup' }} · {{ item.note }}</p></div><small>{{ date(item.created_at) }}</small></div>
    </section>
  </main>

  <footer class="wrap footer"><strong>Ruang CPNS</strong><span>Direktori komunitas untuk persiapan seleksi CPNS.</span></footer>

  <div v-if="modal" class="overlay" @click.self="!busy && (modal='')" @keydown.esc="!busy && (modal='')">
    <form class="dialog" role="dialog" aria-modal="true" aria-labelledby="dialog-title" @submit.prevent="submit">
      <div class="section-head"><h2 id="dialog-title">{{ {login:'Masuk',submit:'Usulkan tautan',edit:'Sunting tautan',report:'Laporkan tautan',resolve:'Tutup laporan'}[modal] }}</h2><button type="button" class="quiet" aria-label="Tutup" :disabled="busy" @click="modal=''">✕</button></div>
      <label v-if="modal==='login'">Email<input v-model="email" type="email" required autocomplete="email"></label>
      <template v-if="modal==='submit' || modal==='edit'">
        <label>Nama sumber<input v-model="form.title" required minlength="2" maxlength="100"></label>
        <label>URL<input v-model="form.url" type="url" required maxlength="2048" placeholder="https://"></label>
        <div class="form-grid">
          <label>Kategori<select v-model="form.category"><option v-for="item in categories" :key="item">{{ item }}</option></select></label>
          <label>Biaya<select v-model="form.price"><option v-for="item in prices" :key="item">{{ item }}</option></select></label>
        </div>
        <label>Deskripsi<textarea v-model="form.description" required minlength="5" maxlength="500"></textarea></label>
      </template>
      <template v-if="modal==='edit'">
        <div class="form-grid">
          <label>Status<select v-model="form.status"><option v-for="(name,key) in statusNames" :key="key" :value="key">{{ name }}</option></select></label>
          <label class="checkbox"><input v-model="form.official" type="checkbox"> Sumber resmi</label>
        </div>
        <p v-if="form.url!==selection.url">Pergantian URL mengembalikan status ke tahap tinjauan.</p>
      </template>
      <p v-if="modal==='report'"><strong>{{ selection.title }}</strong> · Jelaskan masalahnya, misalnya undangan kedaluwarsa atau tautan perlu dihapus.</p>
      <p v-if="modal==='resolve'">{{ resolution.reason }}</p>
      <label v-if="['report','edit','resolve'].includes(modal)">{{ modal==='resolve'?'Hasil peninjauan':'Alasan' }}<textarea v-model="note" required :minlength="modal==='report'?5:2" maxlength="500"></textarea></label>
      <p v-if="notice.error" role="alert" class="error">{{ notice.message }}</p>
      <button class="primary" type="submit" :disabled="busy">{{ busy?'Memproses…':modal==='login'?'Kirim tautan masuk':modal==='submit'?'Kirim usulan':modal==='report'?'Kirim laporan':'Simpan' }}</button>
    </form>
  </div>
  <div v-if="notice.message && !modal" class="toast" role="status"><span>{{ notice.message }}</span><button class="quiet" aria-label="Tutup pesan" @click="notice.message=''">✕</button></div>
</template>

<style>
@import "tailwindcss";
:root{color:#172d28;background:#f6f8f4;font-family:Inter,system-ui,sans-serif}
button{cursor:pointer}button:disabled{opacity:.55;cursor:wait}
.wrap{width:min(1120px,calc(100% - 2.5rem));margin-inline:auto}
.site-header{background:white;border-bottom:1px solid #e3e9e3}
.nav,.nav nav,.section-head,.card-top,.row,.footer,.actions{display:flex;align-items:center;justify-content:space-between;gap:.75rem}
.nav{min-height:76px}.nav nav,.actions{flex-wrap:wrap}
.brand{display:flex;align-items:center;gap:.65rem;font-weight:800;font-size:1.16rem;white-space:nowrap}
.brand-mark,.icon{display:grid;place-items:center;border-radius:10px;width:38px;height:38px;background:#174d3e;color:white}
.primary,.quiet,.filters button{display:inline-flex;align-items:center;justify-content:center;padding:.62rem .9rem;border-radius:8px;font-size:.9rem;font-weight:650;text-decoration:none}
.primary{background:#185441;color:white}.primary:hover{background:#0d382c}.quiet:hover{background:#e6efe7}
.hero{background:#102f26;color:#f4f9f1;overflow:hidden}
.hero-grid{display:grid;grid-template-columns:1.3fr 1fr;align-items:center;min-height:420px;padding-block:3.5rem;gap:2rem}
.eyebrow{color:#b6df93;font-weight:750;font-size:.82rem;letter-spacing:.13em}
h1{font-family:Georgia,serif;font-size:clamp(3rem,7.3vw,6rem);line-height:.96;letter-spacing:-.065em;margin:.75rem 0 1rem}
h1 em{color:#c5ed9e;font-weight:normal}.intro{max-width:420px;color:#d4e4d8;margin-bottom:1.5rem}
.search{background:white;color:#142f25;display:flex;gap:.7rem;align-items:center;padding:.8rem 1rem;border-radius:9px;max-width:455px}.search span{font-size:1.45rem;line-height:1}.search input{width:100%;outline:none}.search:focus-within{outline:3px solid #a0d978}
.hero-art{height:276px;position:relative;isolation:isolate;background:radial-gradient(ellipse,#38674d 0,transparent 70%)}
.art-sheet{width:180px;height:228px;position:absolute;left:calc(50% - 90px);top:20px;border-radius:11px}
.art-back{background:#558169;transform:rotate(-15deg) translateX(-42px);border:1px solid #82a48d}
.art-front{padding:1.25rem;background:#e5f1d8;color:#1e4937;transform:rotate(11deg) translateX(15px);box-shadow:0 14px 32px #06160e80}.art-front span{font-size:.7rem;letter-spacing:.13em;font-weight:800}.art-front strong{display:block;font:700 2.5rem/.95 Georgia;margin:1rem 0}.art-front i{display:block;height:4px;background:#a8c4a0;border-radius:2px;margin-top:8px}.art-front i:last-child{width:60%}.art-check{position:absolute;bottom:20px;left:calc(50% + 64px);background:#b9e590;color:#123e30;border-radius:18px;width:62px;height:62px;display:grid;place-items:center;font-size:2rem;transform:rotate(-10deg)}
.directory{padding-block:2.25rem 3rem}.callout,.empty{padding:1rem;background:#e7eee4;border-radius:9px;margin-bottom:1.2rem}.section-head{margin-bottom:1rem}.section-head p,.card p,.row p,small,.footer{color:#4e6256}
h2{font-size:1.45rem;font-weight:800}h3{font-size:1.24rem;font-weight:800}
.filters{display:flex;flex-wrap:wrap;gap:.5rem;margin-bottom:1.2rem}.filters button{background:white;border:1px solid #d6e1d6}.filters button[aria-pressed=true]{background:#dcebd6;border-color:#8baa83;color:#17432f}
.cards{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:1rem}.card,.panel{background:white;border:1px solid #dbe5da;border-radius:14px;padding:1.15rem}.card{display:flex;flex-direction:column;gap:.55rem}.icon{background:#e1efdb;color:#1d5a41}.pill,.labels span{background:#edf3eb;padding:.24rem .5rem;border-radius:6px;font-size:.78rem;font-weight:700}.labels{display:flex;gap:.4rem;flex-wrap:wrap;margin-top:.2rem}.card-actions{margin-top:auto;padding-top:.55rem;display:flex;flex-wrap:wrap;gap:.25rem}.card-actions .quiet{padding-inline:.55rem}
select,input,textarea{font:inherit}.dialog input:not([type=checkbox]),textarea,select{border:1px solid #aebfb2;border-radius:8px;background:white;padding:.55rem .7rem;width:100%}.section-head select{width:auto}.admin-title{font-size:clamp(2.5rem,5vw,4rem)}.panel{margin-top:1rem}.row{padding:.8rem 0;border-top:1px solid #e4ebe3}.panel h2{margin-bottom:.55rem}
.footer{border-top:1px solid #d8e1d8;padding-block:1.3rem;flex-wrap:wrap}
.overlay{position:fixed;inset:0;background:#0b211ac0;z-index:3;display:grid;place-items:center;padding:1rem}
.dialog{background:white;padding:1.1rem;border-radius:14px;width:min(100%,550px);max-height:calc(100dvh - 2rem);overflow:auto;display:grid;gap:.7rem}.dialog .section-head{margin-bottom:0}.dialog label{display:grid;gap:.28rem;font-weight:650;font-size:.9rem}.form-grid{display:grid;grid-template-columns:1fr 1fr;gap:.6rem}.dialog .checkbox{display:flex;align-items:center}.error{color:#a02424}.toast{position:fixed;z-index:4;bottom:1rem;right:1rem;max-width:calc(100% - 2rem);background:white;border:1px solid #b0c0b0;box-shadow:0 8px 25px #1f352329;padding:.7rem .8rem;border-radius:.6rem;display:flex;align-items:center;gap:.5rem}
@media(max-width:820px){.cards{grid-template-columns:repeat(2,minmax(0,1fr))}}
@media(max-width:620px){.hero-grid{grid-template-columns:1fr;min-height:auto;padding-block:2.4rem}.hero-art{display:none}.cards{grid-template-columns:1fr}.nav{padding-block:.7rem;flex-wrap:wrap}.nav nav{gap:.2rem}.section-head{align-items:flex-start}.row{flex-wrap:wrap}}
</style>
