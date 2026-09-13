import SwiftUI

struct MonogramPicker: View {
    @EnvironmentObject private var app: AppState
    @State private var query: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Монограмма")
                .font(.system(size: 20, weight: .semibold))
            Text("Заготовка библиотеки. Выберите букву или связку — контур попадёт на слой Прожиг или Рез.")
                .font(.system(size: 12))
                .foregroundColor(Theme.mute)
            TextField("Поиск", text: $query)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], spacing: 8) {
                    ForEach(filtered) { symbol in
                        Button {
                            app.addMonogram(symbol)
                        } label: {
                            Text(symbol.title)
                                .font(.system(size: symbol.title.count > 1 ? 16 : 20, weight: .regular, design: .serif))
                                .foregroundColor(Theme.ink)
                                .frame(width: 56, height: 56)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Закрыть") { app.sheet = nil }
                    .buttonStyle(CompactButtonStyle())
            }
        }
        .padding(22)
        .frame(width: 520, height: 480)
        .background(Theme.cream)
    }

    private var filtered: [MonogramSymbol] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return MonogramLibrary.all }
        return MonogramLibrary.all.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.letters.localizedCaseInsensitiveContains(q) }
    }
}
