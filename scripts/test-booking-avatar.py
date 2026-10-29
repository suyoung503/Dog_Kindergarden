#!/usr/bin/env python3
"""Execute the actual booking avatar Swift branch with lightweight view probes (no simulator)."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Dog_kindergarden/Dog_kindergarden/Views/Booking/BookingView.swift').read_text()
section = source.split('private var dogSection: some View {', 1)[1].split('// MARK: - Guardian', 1)[0]
start = section.index('ZStack {')
opening = section.index('{', start)
depth, end = 1, opening + 1
while depth:
    depth += (section[end] == '{') - (section[end] == '}')
    end += 1
avatar = section[start:end]
# This assertion is deliberately specific: authenticated paths and legacy data URLs must
# both reach the existing renderer, rather than selecting an index-based placeholder.
assert 'AuthenticatedPetImage(value: pet.image_url)' in avatar, 'Booking selection always renders the default avatar, ignoring pet.image_url'
assert 'dogBgColors' not in avatar and 'RoundedRectangle' not in avatar, 'Colored square must not sit behind the circular pet photo'
assert 'Circle().stroke' not in section, 'The circular pet portrait must have no outline'
assert '.strokeBorder(vm.selectedPetId == pet.pet_id ? Color.brandOrange : Color.brandBeigeBorder, lineWidth: 2)' in section, 'The outer card needs a uniform inset 2pt selection border'
assert 'vm.selectedPetId = pet.pet_id' in section
assert 'vm.selectedPetId == pet.pet_id ? Color.brandOrange : Color.brandBeigeBorder' in section
swift = '''
struct Probe {
    var values: [String]
    func fill(_ color: Int) -> Self { self }
    func frame(width: Int, height: Int) -> Self { Probe(values: values + ["frame:\\(width)x\\(height)"]) }
    func resizable() -> Self { self }
    func scaledToFit() -> Self { self }
    func clipShape(_ shape: Circle) -> Self { Probe(values: values + ["circle"]) }
}
struct Circle {}
enum Radius { static let lg = 1 }
func RoundedRectangle(cornerRadius: Int) -> Probe { Probe(values: ["background"]) }
func Image(_ name: String) -> Probe { Probe(values: ["default:" + name]) }
func AuthenticatedPetImage(value: String?) -> Probe { Probe(values: ["photo:" + (value ?? "nil")]) }
func dogAvatarName(_ idx: Int) -> String { "avatar-\\(idx)" }
let dogBgColors = [1, 2]
struct Pet { let image_url: String? }
@resultBuilder struct ProbeBuilder {
    static func buildBlock(_ children: Probe...) -> Probe { Probe(values: children.flatMap { $0.values }) }
    static func buildEither(first: Probe) -> Probe { first }
    static func buildEither(second: Probe) -> Probe { second }
}
func ZStack(@ProbeBuilder content: () -> Probe) -> Probe { content() }
func avatarFor(_ pet: Pet, idx: Int) -> Probe {
''' + avatar + '''
}
for (idx, photo) in ["/api/pets/11/photo", "data:image/jpeg;base64,YWJj", nil, "/api/pets/22/photo"].enumerated() {
    let output = avatarFor(Pet(image_url: photo), idx: idx).values
    if let photo {
        precondition(output.contains("photo:" + photo), "Each pet must use its own photo value")
        precondition(!output.contains(where: { $0.hasPrefix("default:") }), "Photo must replace default avatar")
        precondition(output.contains("frame:48x48") && output.contains("circle"), "Photo must be a 48pt circle")
    } else {
        precondition(output.contains("default:avatar-2"), "Missing photo must retain index-based default")
        precondition(output.contains("frame:48x48"), "Default must also fill the 48pt circle")
        precondition(!output.contains(where: { $0.hasPrefix("photo:") }))
    }
    precondition(output.contains("frame:48x48"), "Profile must fill the old 48pt background area")
}
print("PASS: authenticated URL, base64, nil fallback, other pet; 48pt circle with no colored square")
'''
with tempfile.TemporaryDirectory(prefix='booking-avatar-') as tmp:
    path = Path(tmp)
    (path / 'Regression.swift').write_text(swift)
    subprocess.run(['swiftc', '-module-cache-path', str(path / 'cache'), str(path / 'Regression.swift'), '-o', str(path / 'test')], check=True)
    subprocess.run([str(path / 'test')], check=True)
print('PASS: existing selection action and border wiring')
