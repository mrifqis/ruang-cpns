# Ruang CPNS

Direktori tautan persiapan CPNS berbasis Nuxt, Tailwind, dan Supabase. Pengunjung bisa mencari dan memfilter tanpa login. Anggota masuk melalui tautan email untuk mengirim usulan, mengonfirmasi tautan masih aktif, atau mengajukan laporan termasuk permintaan penghapusan.

## Jalankan lokal

Gunakan Node.js 22 atau lebih baru.

```sh
npm ci
npm run dev
```

Tanpa konfigurasi Supabase, aplikasi tampil dalam mode pratinjau dengan dua contoh sumber resmi.

## Hubungkan Supabase

1. Buat proyek Supabase dan jalankan `supabase/schema.sql` sekali melalui SQL Editor pada proyek baru. Skrip membuat tabel, kebijakan akses, fungsi moderasi, dan dua entri awal.
2. Salin `.env.example` ke `.env`. Isi `NUXT_PUBLIC_SUPABASE_URL` dengan Project URL dan `NUXT_PUBLIC_SUPABASE_KEY` dengan publishable key (atau legacy anon key). Simpan service-role/secret key hanya di lingkungan backend yang membutuhkannya. Portal ini tidak memerlukannya.
3. Di Authentication → URL Configuration, isi Site URL dengan alamat produksi, lalu daftar URL pengalihan yang Anda gunakan, misalnya `http://localhost:3000/`. Tautan email masuk kembali ke URL utama aplikasi.
4. Masuk sekali dengan akun yang akan menjadi admin. Di Authentication → Users salin UUID pengguna, lalu jalankan perintah berikut di SQL Editor dengan UUID tersebut.

```sql
insert into public.admins (user_id)
values ('GANTI_DENGAN_UUID_AKUN_ADMIN');
```

5. Muat ulang aplikasi untuk memunculkan menu **Moderasi**. Untuk penggunaan publik, siapkan SMTP proyek Supabase dan uji pengiriman email ke akun eksternal.

## Deploy ke Netlify

Impor repositori yang berisi folder proyek ini ke Netlify. Jika proyek ada dalam subfolder, atur Base directory ke folder tersebut. `netlify.toml` sudah menentukan perintah build dan direktori publikasi. Tambahkan kedua variabel Supabase ke pengaturan build Netlify, jalankan deploy, lalu daftarkan alamat hasil deploy di pengaturan Supabase. Jangan commit `.env`.

Build lokal bisa diperiksa dengan `npm run generate`. Hasil build Netlify berada di `dist`; build lokal standar berada di `.output/public`.

## Alur moderasi

- Usulan baru masuk sebagai **Menunggu tinjauan**. Admin memeriksa tujuan URL dan identitas penerbit, melengkapi metadata, lalu memilih status **Tayang** atau **Ditolak** beserta alasan.
- Badge **Sumber resmi** menunjukkan klasifikasi oleh admin. Jumlah konfirmasi aktif dan tanggal konfirmasi terakhir dihitung dari tanggapan komunitas.
- Pengguna bisa melaporkan tautan, misalnya karena kedaluwarsa, duplikat, isi berubah, atau perlu dihapus. Admin dapat mengedit atau mengarsipkan entri, lalu menutup laporan dengan catatan hasil pemeriksaan.
- Mengganti URL mengembalikan status ke **Menunggu tinjauan** serta menutup tanggapan yang terkait URL lama. Publikasikan kembali setelah URL baru diperiksa.
- Basis data membatasi akun biasa agar hanya dapat mengirim usulan dan umpan balik. Perubahan moderasi dilakukan melalui fungsi yang memeriksa peran admin dan mencatat alasannya.

## Aktifkan Tips & Pengalaman

Untuk portal yang sudah terpasang, jalankan hanya `supabase/migrations/20261126_tips.sql` melalui Supabase SQL Editor. Untuk proyek baru, jalankan `supabase/schema.sql` terlebih dahulu, lalu migrasi tips. Gunakan akun admin yang sudah ditetapkan di `public.admins`.

Pengguna masuk untuk mengirim pengalaman, memberi tanda **Membantu**, atau melaporkan tips. Pilihan tahapan mencakup **Lainnya**. Tahun seleksi dan tautan sumber bersifat opsional. Panel **Moderasi tips** berada di menu **Tips & Pengalaman** dan hanya tersedia bagi admin.

