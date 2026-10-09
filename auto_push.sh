#!/bin/bash

# Jalur absolut ke direktori proyek saat ini
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fungsi utama yang memproses Git
run_git_process() {
    cd "$REPO_DIR" || { echo "❌ Gagal masuk ke direktori proyek."; read -p "Tekan Enter untuk keluar..."; exit 1; }
    
    echo "🚀 Memulai proses Auto Push..."
    echo "------------------------------------------------"

    if [ ! -d ".git" ]; then
        echo "❌ Error: Ini bukan direktori Git."
        echo ""
        read -p "Tekan Enter untuk menutup jendela ini..."
        exit 1
    fi

    echo "📦 Menambahkan perubahan ke staging area..."
    git add .

    echo -n "💬 Masukkan pesan commit (atau Enter untuk default): "
    read commit_msg

    if [ -z "$commit_msg" ]; then
        commit_msg="Update pada $(date '+%Y-%m-%d %H:%M:%S')"
    fi

    git commit -m "$commit_msg"
    
    current_branch=$(git branch --show-current)
    
    if [ -z "$current_branch" ]; then
        echo "❌ Error: Tidak dapat menentukan branch. Apakah sudah ada commit pertama?"
        echo ""
        read -p "Tekan Enter untuk menutup jendela ini..."
        exit 1
    fi

    target_branch="$current_branch"

    echo ""
    echo "📌 Branch aktif saat ini: $current_branch"
    echo -n "👉 Tekan [Enter] untuk push ke '$current_branch', atau ketik 'branch' untuk memilih branch lain: "
    read choice

    # Jika pengguna memilih untuk melihat opsi branch
    if [ "$choice" == "branch" ] || [ "$choice" == "BRANCH" ]; then
        echo ""
        echo "📋 Daftar branch lokal yang tersedia:"
        echo "------------------------------------------------"
        
        # Mengambil daftar branch ke dalam array
        branches=()
        while IFS= read -r line; do
            [ -n "$line" ] && branches+=("$line")
        done < <(git branch --format='%(refname:short)')

        # Menampilkan opsi bernomor
        for i in "${!branches[@]}"; do
            b_name="${branches[$i]}"
            if [ "$b_name" == "$current_branch" ]; then
                echo "  $((i+1)). $b_name (aktif saat ini)"
            else
                echo "  $((i+1)). $b_name"
            fi
        done
        echo "------------------------------------------------"

        # Validasi input nomor dari pengguna
        while true; do
            echo -n "Masukkan nomor branch yang ingin di-push (1-${#branches[@]}): "
            read b_num
            if [[ "$b_num" =~ ^[0-9]+$ ]] && [ "$b_num" -ge 1 ] && [ "$b_num" -le "${#branches[@]}" ]; then
                target_branch="${branches[$((b_num-1))]}"
                break
            else
                echo "⚠️  Pilihan tidak valid. Silakan masukkan nomor antara 1 dan ${#branches[@]}."
            fi
        done
    fi

    echo ""
    echo "🚀 Melakukan push ke origin/$target_branch..."
    
    # Mengecek apakah perintah push berhasil atau gagal
    if git push origin "$target_branch"; then
        echo "------------------------------------------------"
        echo "✅ Selesai! Proses push ke origin/$target_branch berhasil."
    else
        echo "------------------------------------------------"
        echo "❌ Gagal! Terjadi kesalahan saat melakukan push (cek log di atas)."
    fi

    echo ""
    # Skrip akan tertahan di sini sampai kamu menekan Enter
    read -p "Tekan Enter untuk menutup jendela ini..."
}

# Cek apakah skrip ini dipanggil oleh terminal emulator dengan argumen khusus
if [ "$1" == "--run-process" ]; then
    run_git_process
    exit 0
fi

# --- BAGIAN MEMBUKA TERMINAL BARU ---
# Mengecek apakah skrip sudah berjalan di dalam terminal interaktif
if [ -t 1 ]; then
    # Jika sudah ada terminal (misal: kamu jalankan via ./auto_push.sh di terminal), langsung eksekusi
    run_git_process
else
    # Jika tidak ada terminal (misal: double-click dari File Manager GUI)
    # Mengutamakan xfce4-terminal khusus untuk pengguna Linux Lite
    if command -v xfce4-terminal &> /dev/null; then
        xfce4-terminal -x bash "$0" --run-process
    elif command -v gnome-terminal &> /dev/null; then
        gnome-terminal -- bash "$0" --run-process
    elif command -v konsole &> /dev/null; then
        konsole -e "bash \"$0\" --run-process"
    elif command -v alacritty &> /dev/null; then
        alacritty -e bash "$0" --run-process
    elif command -v kitty &> /dev/null; then
        kitty bash "$0" --run-process
    else
        # Fallback jika tidak ada terminal modern yang cocok
        xterm -e bash "$0" --run-process
    fi
fi