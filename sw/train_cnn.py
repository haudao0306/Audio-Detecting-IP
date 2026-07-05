# train_cnn.py

import os
import torch
import torch.nn as nn
import torch.optim as optim
import numpy as np
import random
from torch.utils.data import DataLoader, random_split

from dataset_loader import AudioDataset
from model import AudioCNN
import config


# =========================
# Fix random seed
# =========================
def set_seed(seed=42):
    torch.manual_seed(seed)
    np.random.seed(seed)
    random.seed(seed)

set_seed()


# =========================
# Data loaders
# =========================
def get_loaders():
    dataset = AudioDataset(config.FOLDER_LIST, config.LABEL_IDS)

    if len(dataset) == 0:
        raise ValueError("Dataset is empty! Check your folders.")

    print(f"Total samples: {len(dataset)}")

    val_size   = int(config.VAL_SPLIT * len(dataset))
    train_size = len(dataset) - val_size

    generator = torch.Generator().manual_seed(42)
    train_set, val_set = random_split(
        dataset,
        [train_size, val_size],
        generator=generator
    )

    train_loader = DataLoader(
        train_set,
        batch_size=config.BATCH_SIZE,
        shuffle=True,
        num_workers=2,
        pin_memory=True
    )

    val_loader = DataLoader(
        val_set,
        batch_size=config.BATCH_SIZE,
        shuffle=False,
        num_workers=2,
        pin_memory=True
    )

    return train_loader, val_loader, val_set


# =========================
# Training
# =========================
def train():
    # ── Device ─────────────────────────
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Using device: {device}")

    # ── Data ───────────────────────────
    train_loader, val_loader, val_set = get_loaders()

    # ── Model ──────────────────────────
    model = AudioCNN(n_classes=config.NUM_CLASSES).to(device)
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=config.LEARNING_RATE)

    # ── Fix checkpoint path ──
    checkpoint_dir = os.path.dirname(config.CHECKPOINT_PATH)
    if checkpoint_dir:
        os.makedirs(checkpoint_dir, exist_ok=True)

    # ── Training loop ───────────────────
    best_val_acc = 0
    no_improve   = 0

    for epoch in range(config.EPOCHS):

        # ===== TRAIN =====
        model.train()
        total_loss, total_correct, total_samples = 0, 0, 0

        for X, y in train_loader:
            X, y = X.to(device), y.to(device)

            optimizer.zero_grad()

            outputs = model(X)
            loss    = criterion(outputs, y)

            loss.backward()

            # gradient clipping
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)

            optimizer.step()

            total_loss    += loss.item() * X.size(0)
            total_correct += (outputs.argmax(1) == y).sum().item()
            total_samples += y.size(0)

        train_loss = total_loss / total_samples
        train_acc  = total_correct / total_samples

        # ===== VALIDATION =====
        model.eval()
        val_loss, val_correct, val_samples = 0, 0, 0

        with torch.no_grad():
            for X, y in val_loader:
                X, y = X.to(device), y.to(device)

                outputs = model(X)
                loss    = criterion(outputs, y)

                val_loss    += loss.item() * X.size(0)
                val_correct += (outputs.argmax(1) == y).sum().item()
                val_samples += y.size(0)

        val_loss /= val_samples
        val_acc   = val_correct / val_samples

        print(f"Epoch {epoch+1}/{config.EPOCHS} | "
              f"Train Loss: {train_loss:.4f} | Train Acc: {train_acc:.4f} | "
              f"Val Loss: {val_loss:.4f} | Val Acc: {val_acc:.4f}")

        # ===== EARLY STOPPING =====
        if val_acc > best_val_acc:
            best_val_acc = val_acc
            no_improve   = 0

            torch.save(model.state_dict(), config.CHECKPOINT_PATH)
            print("  ✅ Saved best model!")
        else:
            no_improve += 1
            if no_improve >= config.PATIENCE:
                print("Early stopping triggered!")
                break

    # ── Load lại best model ─────────────
    model.load_state_dict(torch.load(config.CHECKPOINT_PATH))
    print(f"Training finished! Best Val Acc: {best_val_acc:.4f}")
    print("👉 Hãy chạy tiếp file 'cnnpth_export_to_hex.py' để trích xuất file .hex cho Verilog.")


# =========================
# Run
# =========================
if __name__ == "__main__":
    train()