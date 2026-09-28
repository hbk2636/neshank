import Foundation
import SQLite3

// MARK: - خطاها

enum DBError: LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let m): return L.tf("Error opening database: %@", m)
        case .prepareFailed(let m): return L.tf("SQL command error: %@", m)
        case .stepFailed(let m): return L.tf("SQL execution error: %@", m)
        }
    }
}

// MARK: - مقدار

enum SQLValue {
    case null
    case int(Int64)
    case real(Double)
    case text(String)
    case data(Data)
}

// MARK: - ردیف

struct DBRow {
    private let values: [String: SQLValue]

    init(values: [String: SQLValue]) { self.values = values }

    subscript(name: String) -> SQLValue? { values[name] }

    func int(_ name: String) -> Int64? {
        guard let v = values[name] else { return nil }
        switch v {
        case .int(let i): return i
        case .real(let d): return Int64(d)
        case .text(let t): return Int64(t)
        default: return nil
        }
    }

    func double(_ name: String) -> Double? {
        guard let v = values[name] else { return nil }
        switch v {
        case .real(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }

    func text(_ name: String) -> String? {
        guard case .text(let t)? = values[name] else { return nil }
        return t
    }

    func textOrEmpty(_ name: String) -> String { text(name) ?? "" }

    func bool(_ name: String) -> Bool { (int(name) ?? 0) != 0 }
}

// MARK: - فرمان آماده

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class DBStatement {
    private let stmt: OpaquePointer
    private let db: OpaquePointer

    init(stmt: OpaquePointer, db: OpaquePointer) {
        self.stmt = stmt
        self.db = db
    }

    func finalize() { sqlite3_finalize(stmt) }

    var lastError: String { String(cString: sqlite3_errmsg(db)) }

    func bind(_ params: [SQLValue]) throws {
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            let rc: Int32
            switch p {
            case .null:
                rc = sqlite3_bind_null(stmt, idx)
            case .int(let v):
                rc = sqlite3_bind_int64(stmt, idx, v)
            case .real(let v):
                rc = sqlite3_bind_double(stmt, idx, v)
            case .text(let v):
                rc = sqlite3_bind_text(stmt, idx, v, -1, sqliteTransient)
            case .data(let v):
                rc = v.withUnsafeBytes { buf in
                    sqlite3_bind_blob(stmt, idx, buf.baseAddress, Int32(buf.count), sqliteTransient)
                }
            }
            if rc != SQLITE_OK { throw DBError.prepareFailed(lastError) }
        }
    }

    @discardableResult
    func step() -> Int32 { sqlite3_step(stmt) }

    func row() -> DBRow {
        var values: [String: SQLValue] = [:]
        let count = sqlite3_column_count(stmt)
        for i in 0..<count {
            let namePtr = sqlite3_column_name(stmt, i)
            let name = namePtr.map { String(cString: $0) } ?? "col\(i)"
            switch sqlite3_column_type(stmt, i) {
            case SQLITE_INTEGER:
                values[name] = .int(sqlite3_column_int64(stmt, i))
            case SQLITE_FLOAT:
                values[name] = .real(sqlite3_column_double(stmt, i))
            case SQLITE_TEXT:
                if let c = sqlite3_column_text(stmt, i) {
                    values[name] = .text(String(cString: c))
                } else {
                    values[name] = .text("")
                }
            case SQLITE_BLOB:
                if let bytes = sqlite3_column_blob(stmt, i) {
                    let n = Int(sqlite3_column_bytes(stmt, i))
                    values[name] = .data(Data(bytes: bytes, count: n))
                } else {
                    values[name] = .data(Data())
                }
            default:
                values[name] = .null
            }
        }
        return DBRow(values: values)
    }

    /// مقدار ستون اول ردیف جاری (برای scalar)
    func firstInt() -> Int64? {
        guard sqlite3_column_count(stmt) > 0 else { return nil }
        switch sqlite3_column_type(stmt, 0) {
        case SQLITE_INTEGER: return sqlite3_column_int64(stmt, 0)
        case SQLITE_FLOAT: return Int64(sqlite3_column_double(stmt, 0))
        case SQLITE_TEXT:
            if let c = sqlite3_column_text(stmt, 0) { return Int64(String(cString: c)) }
            return nil
        default: return nil
        }
    }
}

// MARK: - پایگاه داده

final class Database {
    private let handle: OpaquePointer

    init(path: String) throws {
        var h: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &h, flags, nil)
        guard rc == SQLITE_OK, let opened = h else {
            let msg = h.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let h { sqlite3_close(h) }
            throw DBError.openFailed(msg)
        }
        handle = opened
        try exec("PRAGMA foreign_keys = ON;")
        try exec("PRAGMA journal_mode = WAL;")
        try exec("PRAGMA synchronous = NORMAL;")
        try exec("PRAGMA busy_timeout = 4000;")
    }

    deinit { sqlite3_close(handle) }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw DBError.stepFailed(msg)
        }
    }

    private func prepare(_ sql: String) throws -> DBStatement {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &st, nil) == SQLITE_OK, let st else {
            throw DBError.prepareFailed(String(cString: sqlite3_errmsg(handle)))
        }
        return DBStatement(stmt: st, db: handle)
    }

    @discardableResult
    func run(_ sql: String, _ params: [SQLValue] = []) throws -> Int64 {
        let st = try prepare(sql)
        defer { st.finalize() }
        try st.bind(params)
        guard st.step() == SQLITE_DONE else { throw DBError.stepFailed(st.lastError) }
        return sqlite3_last_insert_rowid(handle)
    }

    func rows(_ sql: String, _ params: [SQLValue] = []) throws -> [DBRow] {
        let st = try prepare(sql)
        defer { st.finalize() }
        try st.bind(params)
        var out: [DBRow] = []
        while true {
            let rc = st.step()
            if rc == SQLITE_ROW {
                out.append(st.row())
            } else if rc == SQLITE_DONE {
                return out
            } else {
                throw DBError.stepFailed(st.lastError)
            }
        }
    }

    /// مقدار ستون اولِ اولین ردیف (یا nil)
    func scalarInt(_ sql: String, _ params: [SQLValue] = []) throws -> Int64? {
        let st = try prepare(sql)
        defer { st.finalize() }
        try st.bind(params)
        let rc = st.step()
        if rc == SQLITE_ROW { return st.firstInt() }
        if rc == SQLITE_DONE { return nil }
        throw DBError.stepFailed(st.lastError)
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN;")
        do {
            let out = try body()
            try exec("COMMIT;")
            return out
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }
}
