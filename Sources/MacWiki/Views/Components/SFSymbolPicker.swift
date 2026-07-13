import SwiftUI

/// A searchable grid picker for SF Symbols
struct SFSymbolPicker: View {
    @Binding var selectedSymbol: String
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    
    // Organized by category with ~200 popular symbols
    private let categories: [(name: String, symbols: [String])] = [
        ("Bookmarks & Lists", [
            "bookmark.fill", "bookmark", "bookmark.circle.fill", "bookmark.square.fill",
            "list.bullet", "list.number", "list.star", "list.bullet.rectangle",
            "text.badge.star", "text.badge.checkmark", "checklist", "checklist.checked"
        ]),
        ("Stars & Favorites", [
            "star.fill", "star", "star.circle.fill", "star.square.fill",
            "star.leadinghalf.filled", "sparkles", "sparkle", "staroflife.fill"
        ]),
        ("Hearts & Love", [
            "heart.fill", "heart", "heart.circle.fill", "heart.square.fill",
            "heart.text.square.fill", "bolt.heart.fill", "arrow.up.heart.fill"
        ]),
        ("Folders & Files", [
            "folder.fill", "folder", "folder.circle.fill", "folder.badge.plus",
            "doc.fill", "doc.text.fill", "doc.richtext.fill", "doc.plaintext.fill",
            "archivebox.fill", "tray.fill", "tray.2.fill", "externaldrive.fill"
        ]),
        ("Books & Reading", [
            "book.fill", "book", "book.closed.fill", "books.vertical.fill",
            "text.book.closed.fill", "bookmark.fill", "newspaper.fill", "magazine.fill",
            "character.book.closed.fill", "menucard.fill"
        ]),
        ("Media & Entertainment", [
            "play.fill", "film.fill", "tv.fill", "music.note", "music.note.list",
            "headphones", "speaker.wave.3.fill", "video.fill", "photo.fill",
            "camera.fill", "gamecontroller.fill", "theatermasks.fill"
        ]),
        ("Science & Nature", [
            "leaf.fill", "atom", "globe.americas.fill", "globe.europe.africa.fill",
            "sun.max.fill", "moon.fill", "star.fill", "cloud.fill",
            "flame.fill", "drop.fill", "snowflake", "bolt.fill",
            "pawprint.fill", "tortoise.fill", "hare.fill", "bird.fill",
            "fish.fill", "ant.fill", "ladybug.fill", "tree.fill"
        ]),
        ("Technology", [
            "desktopcomputer", "laptopcomputer", "iphone", "ipad",
            "applewatch", "airpodspro", "homepod.fill", "appletv.fill",
            "cpu.fill", "memorychip.fill", "wifi", "antenna.radiowaves.left.and.right",
            "network", "server.rack", "externaldrive.fill", "opticaldisc.fill"
        ]),
        ("People & Communication", [
            "person.fill", "person.2.fill", "person.3.fill", "figure.stand",
            "bubble.left.fill", "bubble.right.fill", "phone.fill", "envelope.fill",
            "at", "bell.fill", "megaphone.fill", "quote.bubble.fill"
        ]),
        ("Arrows & Navigation", [
            "arrow.right", "arrow.left", "arrow.up", "arrow.down",
            "arrow.clockwise", "arrow.counterclockwise", "arrow.triangle.branch",
            "location.fill", "mappin.and.ellipse", "map.fill", "safari.fill"
        ]),
        ("Shapes & Symbols", [
            "circle.fill", "square.fill", "triangle.fill", "diamond.fill",
            "hexagon.fill", "octagon.fill", "seal.fill", "shield.fill",
            "flag.fill", "tag.fill", "rosette", "crown.fill"
        ]),
        ("Tools & Objects", [
            "wrench.fill", "hammer.fill", "screwdriver.fill", "paintbrush.fill",
            "pencil", "highlighter", "scissors", "ruler.fill",
            "briefcase.fill", "suitcase.fill", "backpack.fill", "handbag.fill",
            "graduation.cap.fill", "gift.fill", "cart.fill", "bag.fill"
        ]),
        ("Food & Drink", [
            "cup.and.saucer.fill", "mug.fill", "wineglass.fill", "takeoutbag.and.cup.and.straw.fill",
            "fork.knife", "birthday.cake.fill", "carrot.fill", "leaf.fill"
        ]),
        ("Sports & Fitness", [
            "figure.run", "figure.walk", "figure.hiking", "figure.yoga",
            "dumbbell.fill", "sportscourt.fill", "soccerball", "basketball.fill",
            "football.fill", "baseball.fill", "tennisball.fill", "volleyball.fill"
        ]),
        ("Health & Medical", [
            "heart.fill", "cross.fill", "pills.fill", "syringe.fill",
            "bandage.fill", "stethoscope", "brain.head.profile", "lungs.fill",
            "eye.fill", "ear.fill", "hand.raised.fill", "allergens"
        ]),
        ("Finance & Business", [
            "dollarsign.circle.fill", "eurosign.circle.fill", "sterlingsign.circle.fill",
            "creditcard.fill", "banknote.fill", "chart.bar.fill", "chart.pie.fill",
            "chart.line.uptrend.xyaxis", "building.2.fill", "building.columns.fill"
        ]),
        ("Weather & Time", [
            "sun.max.fill", "moon.stars.fill", "cloud.fill", "cloud.rain.fill",
            "cloud.snow.fill", "wind", "thermometer.medium", "umbrella.fill",
            "clock.fill", "alarm.fill", "timer", "stopwatch.fill",
            "calendar", "calendar.circle.fill"
        ]),
        ("Music & Audio", [
            "music.note", "music.note.list", "music.quarternote.3", "music.mic",
            "pianokeys", "guitars.fill", "dial.high.fill", "waveform",
            "speaker.wave.3.fill", "hifispeaker.fill", "headphones", "airpods"
        ]),
        ("Misc & Fun", [
            "lightbulb.fill", "lightbulb.max.fill", "flashlight.on.fill",
            "puzzlepiece.fill", "dice.fill", "paintpalette.fill", "theatermasks.fill",
            "party.popper.fill", "balloon.fill", "fireworks", "wand.and.stars"
        ])
    ]
    
    private var allSymbols: [String] {
        categories.flatMap { $0.symbols }
    }
    
    private var filteredSymbols: [String] {
        if searchText.isEmpty {
            return allSymbols
        }
        return allSymbols.filter { $0.localizedStandardContains(searchText) }
    }
    
    private var filteredCategories: [(name: String, symbols: [String])] {
        if searchText.isEmpty {
            return categories
        }
        return categories.compactMap { category in
            let filtered = category.symbols.filter { $0.localizedStandardContains(searchText) }
            return filtered.isEmpty ? nil : (category.name, filtered)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Choose Icon")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search symbols...", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear symbol search")
                }
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            
            Divider()
                .padding(.top, 12)
            
            // Symbol Grid
            ScrollView {
                if searchText.isEmpty {
                    // Show by category
                    LazyVStack(alignment: .leading, spacing: 16, pinnedViews: .sectionHeaders) {
                        ForEach(categories, id: \.name) { category in
                            Section {
                                symbolGrid(for: category.symbols)
                            } header: {
                                Text(category.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                    .background(.background)
                            }
                        }
                    }
                    .padding()
                } else {
                    // Show filtered results
                    if filteredSymbols.isEmpty {
                        ContentUnavailableView(
                            "No Matching Symbols",
                            systemImage: "magnifyingglass",
                            description: Text("Try a different search term.")
                        )
                        .padding()
                    } else {
                        symbolGrid(for: filteredSymbols)
                            .padding()
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
        .onAppear {
            searchText = ""
            isSearchFocused = true
        }
    }
    
    private func symbolGrid(for symbols: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 40, maximum: 48), spacing: 8)], spacing: 8) {
            ForEach(symbols, id: \.self) { symbol in
                Button {
                    selectedSymbol = symbol
                    dismiss()
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 18))
                        .foregroundStyle(selectedSymbol == symbol ? Color.accentColor : .secondary)
                        .frame(width: 40, height: 40)
                        .background(
                            selectedSymbol == symbol
                                ? Color.accentColor.opacity(0.1)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .overlay {
                            if selectedSymbol == symbol {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(symbol)
                .accessibilityLabel("Select \(symbol)")
                .accessibilityValue(selectedSymbol == symbol ? "Selected" : "")
            }
        }
    }
}

#Preview {
    SFSymbolPicker(selectedSymbol: .constant("star.fill"))
}
