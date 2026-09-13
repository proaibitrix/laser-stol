import SwiftUI

struct NewTagWizard: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    shapeRow
                    HStack(alignment: .top, spacing: 24) {
                        previewCard
                        sizeFields
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 16)
            }
            nextBar
        }
        .frame(minWidth: 620, idealWidth: 720, maxWidth: 820, minHeight: 460, idealHeight: 560)
        .creamSurface()
        .background(Theme.cream)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("1")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.ink)
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(Theme.line, lineWidth: 1))
            Text("Новая бирка")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(Theme.ink)
            Text("Выберите форму и размер бирки")
                .font(.system(size: 12))
                .foregroundColor(Theme.mute)
        }
        .frame(maxWidth: .infinity)
    }

    private var shapeRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("1. Выберите форму")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.ink)
            HStack(spacing: 12) {
                shapeCard(.rectangle, title: "Прямоугольник", subtitle: "Классическая форма", icon: "rectangle")
                shapeCard(.oval, title: "Овал", subtitle: "Мягкая и аккуратная", icon: "oval")
                shapeCard(.custom, title: "Свой размер", subtitle: "Задайте размеры под свой дизайн", icon: "square.dashed")
            }
        }
    }

    private func shapeCard(_ shape: TagDraft.Shape, title: String, subtitle: String, icon: String) -> some View {
        let selected = app.draftTag.shape == shape
        return Button {
            app.draftTag.shape = shape
        } label: {
            VStack(spacing: 8) {
                HStack {
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Theme.terracotta)
                            .font(.system(size: 13))
                    }
                }
                .frame(height: 14)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(Theme.terracotta)
                    .frame(height: 26)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.ink)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.mute)
                    .multilineTextAlignment(.center)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 108)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Theme.terracottaSoft : Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? Theme.terracotta.opacity(0.55) : Theme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("2. Предпросмотр бирки")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.ink)
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                TagPreview(draft: app.draftTag)
                    .frame(width: 160, height: 110)
            }
            .frame(width: 260, height: 150)
        }
    }

    private var sizeFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("3. Размеры (мм)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.ink)
            stepper("Ширина", value: $app.draftTag.widthMM)
            stepper("Высота", value: $app.draftTag.heightMM)
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.terracotta)
                Text("Размеры можно изменить на столе после вставки.")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.mute)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepper(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.ink)
                .frame(width: 72, alignment: .leading)
            HStack(spacing: 0) {
                Button("−") { value.wrappedValue = max(8.0, value.wrappedValue - 1) }
                    .foregroundColor(Theme.ink)
                    .frame(width: 28, height: 28)
                Text(String(format: "%.0f", value.wrappedValue))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.ink)
                    .frame(width: 54)
                Text("мм")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.mute)
                    .padding(.trailing, 8)
                Button("+") { value.wrappedValue = min(400.0, value.wrappedValue + 1) }
                    .foregroundColor(Theme.ink)
                    .frame(width: 28, height: 28)
            }
            .background(Capsule().fill(Theme.card))
            .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
            .buttonStyle(.plain)
        }
    }

    private var nextBar: some View {
        Button {
            app.addTag(from: app.draftTag)
        } label: {
            HStack {
                Spacer()
                Text("Дальше")
                    .font(.system(size: 14, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .foregroundColor(Color(red: 1, green: 1, blue: 1))
            .frame(height: 44)
            .background(Theme.terracotta)
        }
        .buttonStyle(.plain)
    }
}

struct TagPreview: View {
    var draft: TagDraft

    var body: some View {
        ZStack {
            tagShape
                .fill(Color(red: 1, green: 1, blue: 1))
                .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
            tagShape
                .stroke(Theme.terracotta.opacity(0.35), lineWidth: 1)
            VStack(spacing: 6) {
                Circle()
                    .stroke(Theme.terracotta.opacity(0.45), lineWidth: 1)
                    .frame(width: 10, height: 10)
                Text("И")
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .foregroundColor(Theme.terracotta)
            }
        }
        .frame(width: draft.shape == .oval ? 132 : 148, height: draft.shape == .oval ? 88 : 86)
    }

    private var tagShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: draft.shape == .oval ? 40 : 10, style: .continuous)
    }
}
