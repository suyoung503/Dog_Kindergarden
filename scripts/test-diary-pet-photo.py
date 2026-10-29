#!/usr/bin/env python3
"""Compile actual DTO/context/URL resolver declarations without Xcode or networking."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
app = root / 'Dog_kindergarden/Dog_kindergarden'

def declaration(path, start):
    source = (app / path).read_text()
    begin = source.index(start)
    opening = source.index('{', begin)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[begin:end]

source = '''import Foundation
enum APIEnvironment { static let apiBaseURL = URL(string: "https://example.invalid/api")! }
''' + '\n'.join([
    declaration('APIClient.swift', 'struct ReservationSummary:'),
    declaration('APIClient.swift', 'struct PendingReservation:'),
    declaration('Views/Navigation/AppRouter.swift', 'struct DiaryContext'),
    declaration('Views/DogProfile/PetPhotoSupport.swift', 'enum PetPhotoURLResolver'),
]) + '''
@main struct Regression {
    @MainActor static func main() throws {
        let base = URL(string: "https://example.invalid/api")!
        for path in ["/api/pets/7/photo", "/api/reservations/19/pet-photo"] {
            precondition(PetPhotoURLResolver.resolve(path, baseURL: base)?.absoluteString == "https://example.invalid" + path)
        }
        for path in ["https://evil.example/api/reservations/19/pet-photo", "//evil.example/api/reservations/19/pet-photo",
                     "/api/reservations/19/pet-photo?token=secret", "/api/reservations/19/pet-photo#token", "/api/reservations/19",
                     "/api/reservations/0/pet-photo", "/api/reservations/19/diaries", "/api/reservations/19/pet-photo/extra",
                     "https://example.invalid:444/api/reservations/19/pet-photo", "https://user:pass@example.invalid/api/reservations/19/pet-photo"] {
            precondition(PetPhotoURLResolver.resolve(path, baseURL: base) == nil, path)
        }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        for raw in [#"{"reservation_id":19,"pet_name":"초코","pet_image_url":"/api/reservations/19/pet-photo"}"#,
                    #"{"reservation_id":19,"pet_image_url":"data:image/jpeg;base64,YWJj"}"#,
                    #"{"reservation_id":19,"pet_image_url":null}"#, #"{"reservation_id":19}"#] {
            let data = Data(raw.utf8)
            let guardian = try decoder.decode(ReservationSummary.self, from: data)
            let owner = try decoder.decode(PendingReservation.self, from: data)
            precondition(guardian.petImageUrl == owner.petImageUrl)
            let context = DiaryContext(reservationId: 19, petName: "초코", storeName: "가게", canWrite: true, petImageUrl: owner.petImageUrl)
            precondition(context.petImageUrl == owner.petImageUrl)
        }
        precondition(DiaryContext(reservationId: 19, petName: "초코", storeName: "가게", canWrite: false).petImageUrl == nil)
        print("PASS Swift diary photo DTO, context, strict same-origin URL compatibility")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='diary-pet-photo-') as tmp:
    swift, binary = Path(tmp) / 'Regression.swift', Path(tmp) / 'regression'
    swift.write_text(source)
    subprocess.run(['swiftc', '-module-cache-path', str(Path(tmp) / 'module-cache'), '-parse-as-library', str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
for path in ['Views/Diary/MyDiaryListView.swift', 'Views/Owner/OwnerDiaryListView.swift']:
    view = (app / path).read_text()
    assert 'AuthenticatedPetImage(value: reservation.petImageUrl)' in view
    assert 'petImageUrl: reservation.petImageUrl' in view
    assert '.clipShape(Circle())' in view
assert 'AuthenticatedPetImage(value: context?.petImageUrl)' in (app / 'Views/Diary/DiaryTimelineView.swift').read_text()
print('PASS guardian/owner circular portrait and timeline photo context wiring')

# Exercise the production renderer's exact branches with lightweight Swift view probes.
renderer = declaration('Views/DogProfile/PetPhotoSupport.swift', 'struct AuthenticatedPetImage:')
assert 'Image("dog_c").resizable().scaledToFit()' in renderer, 'Missing or failed pet photos must use the bundled dog_c asset'
assert 'pawprint' not in renderer, 'Photo fallback must not render a paw icon'
assert (app / 'Assets.xcassets/dog_c.imageset/dog_c.png').is_file()
body = renderer.split('var body: some View {', 1)[1].split('.task(id: value)', 1)[0].strip()
probe = r'''
struct Probe {
    let values: [String]
    func resizable() -> Self { Probe(values: values + ["resizable"]) }
    func scaledToFill() -> Self { Probe(values: values + ["fill"]) }
    func scaledToFit() -> Self { Probe(values: values + ["fit"]) }
}
struct UIImage {}
func Image(_ name: String) -> Probe { Probe(values: ["asset:" + name]) }
func Image(uiImage: UIImage) -> Probe { Probe(values: ["actual-photo"]) }
@resultBuilder struct ProbeBuilder {
    static func buildBlock(_ child: Probe) -> Probe { child }
    static func buildEither(first: Probe) -> Probe { first }
    static func buildEither(second: Probe) -> Probe { second }
}
func Group(@ProbeBuilder content: () -> Probe) -> Probe { content() }
func avatar(image: UIImage?) -> Probe {
''' + body + r'''
}
precondition(avatar(image: UIImage()).values == ["actual-photo", "resizable", "fill"], "Loaded photo must replace fallback")
precondition(avatar(image: nil).values == ["asset:dog_c", "resizable", "fit"], "Missing or failed photo must show dog_c")
print("PASS actual photo/fallback rendering branches")
'''
with tempfile.TemporaryDirectory(prefix='pet-image-fallback-') as tmp:
    path = Path(tmp)
    (path / 'Regression.swift').write_text(probe)
    subprocess.run(['swiftc', '-module-cache-path', str(path / 'cache'), str(path / 'Regression.swift'), '-o', str(path / 'test')], check=True)
    subprocess.run([str(path / 'test')], check=True)
assert 'image = UIImage(data: bytes)' in renderer and 'catch { image = nil }' in renderer
assert 'OwnerReservationCard(reservation: reservation' in (app / 'Views/Owner/OwnerModeView.swift').read_text()
for path in ['Views/Owner/OwnerDiaryListView.swift', 'Views/Owner/OwnerReservationDetailView.swift']:
    view = (app / path).read_text()
    assert 'AuthenticatedPetImage(value:' in view
    assert 'pawprint' not in view
owner_detail = (app / 'Views/Owner/OwnerReservationDetailView.swift').read_text()
assert 'row("메모 원문"' not in owner_detail, 'Raw memo row must not duplicate parsed notes'
for label in ['사회성', '알레르기', '특이사항']:
    assert 'row("' + label + '"' in owner_detail
print('PASS owner cards/detail use actual photo renderer and do not duplicate raw notes')
