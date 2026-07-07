//
//  DataManager.swift
//  Dog_kindergarden
//
//  맡겨멍 MVP 데이터 로더
//

import Foundation

struct DogCareStore: Hashable {
    let id: String
    let name: String
    let status: String
    let roadAddress: String
    let lotAddress: String
    let phone: String
    let x: String
    let y: String

    var displayAddress: String {
        if !roadAddress.isEmpty { return roadAddress }
        if !lotAddress.isEmpty { return lotAddress }
        return "주소 정보 없음"
    }

    var isOpen: Bool {
        status == "영업" || status == "정상" || status == "운영중"
    }

    var badges: [String] {
        var result = ["예약요청", "알림장"]
        if name.contains("호텔") || name.contains("스테이") { result.append("호텔") }
        if name.contains("유치원") || name.contains("데이케어") { result.append("유치원") }
        if name.contains("케어") { result.append("케어") }
        return Array(Set(result)).sorted()
    }
}

final class DataManager {
    enum DataError: Error {
        case fileNotFound
        case unreadable
    }

    func loadStores() -> [DogCareStore] {
        do {
            let stores = try loadCSVStores()
            return stores
        } catch {
            print("CSV 로드 실패: \(error)")
            return sampleStores
        }
    }

    private func loadCSVStores() throws -> [DogCareStore] {
        guard let url = Bundle.main.url(forResource: "All_data", withExtension: "csv") else {
            throw DataError.fileNotFound
        }

        let rawData = try Data(contentsOf: url)
        guard let text = String(data: rawData, encoding: .utf8)
            ?? String(data: rawData, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosKorean.rawValue))))
            ?? String(data: rawData, encoding: .init(rawValue: 949)) else {
            throw DataError.unreadable
        }

        let rows = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard rows.count > 1 else { return [] }

        let header = parseCSVLine(rows[0])
        let indexes = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($0.element, $0.offset) })

        func value(_ name: String, in columns: [String]) -> String {
            guard let index = indexes[name], columns.indices.contains(index) else { return "" }
            return columns[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let stores = rows.dropFirst().compactMap { row -> DogCareStore? in
            let columns = parseCSVLine(row)
            let name = value("사업장명", in: columns)
            guard !name.isEmpty, isDogHotel(name) else { return nil }

            return DogCareStore(
                id: value("관리번호", in: columns).isEmpty ? UUID().uuidString : value("관리번호", in: columns),
                name: name,
                status: value("상세영업상태명", in: columns).isEmpty ? value("영업상태명", in: columns) : value("상세영업상태명", in: columns),
                roadAddress: value("도로명주소", in: columns),
                lotAddress: value("지번주소", in: columns),
                phone: value("전화번호", in: columns),
                x: value("좌표정보(X)", in: columns),
                y: value("좌표정보(Y)", in: columns)
            )
        }

        // 현재 운영 중인 곳을 우선 노출하고 이름순 정렬
        return stores.sorted { lhs, rhs in
            if lhs.isOpen != rhs.isOpen { return lhs.isOpen && !rhs.isOpen }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }

    func isDogHotel(_ name: String) -> Bool {
        let includeKeywords = ["호텔", "유치원", "데이케어", "스테이", "케어", "놀이방", "반려견"]
        let excludeKeywords = ["동물병원", "병원", "사료", "용품", "미용", "약국"]

        if excludeKeywords.contains(where: { name.contains($0) }) { return false }
        return includeKeywords.contains(where: { name.contains($0) })
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var columns: [String] = []
        var current = ""
        var insideQuotes = false
        var iterator = line.makeIterator()

        while let char = iterator.next() {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                columns.append(current.replacingOccurrences(of: "\"\"", with: "\""))
                current = ""
            } else {
                current.append(char)
            }
        }
        columns.append(current.replacingOccurrences(of: "\"\"", with: "\""))
        return columns
    }

    private var sampleStores: [DogCareStore] {
        [
            DogCareStore(id: "sample-1", name: "맡겨멍 강남 유치원", status: "영업", roadAddress: "서울특별시 강남구 테헤란로", lotAddress: "", phone: "02-0000-0000", x: "", y: ""),
            DogCareStore(id: "sample-2", name: "해피퍼피 호텔", status: "영업", roadAddress: "서울특별시 마포구 월드컵북로", lotAddress: "", phone: "02-1111-1111", x: "", y: "")
        ]
    }
}
