import Foundation
import Supabase

/// The app's single Supabase client.
///
/// Credentials come from `Config/Secrets.xcconfig` via Info.plist, so nothing
/// is committed. **Only the anon/publishable key belongs here** — it is
/// designed to ship inside a client and is protected by RLS. The service_role
/// key bypasses RLS entirely; if one ever appears in this file, the entire
/// authorization model (`supabase/migrations/010`) is void.
public enum SupabaseEnvironment {
    public static let shared: SupabaseClient = {
        let bundle = Bundle.main

        guard
            let urlString = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            !urlString.isEmpty,
            let url = URL(string: urlString),
            url.scheme != nil
        else {
            fatalError("""
                SUPABASE_URL missing or malformed.

                Copy Config/Secrets.example.xcconfig to Config/Secrets.xcconfig \
                and fill it in, then re-run `xcodegen generate`.

                If the value looks truncated to "https:", the URL in the \
                xcconfig is missing the $() separator — xcconfig treats "//" \
                as a comment and silently drops the rest of the line.
                """)
        }

        guard
            let key = bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            !key.isEmpty
        else {
            fatalError("SUPABASE_ANON_KEY missing. See Config/Secrets.example.xcconfig.")
        }

        return SupabaseClient(supabaseURL: url, supabaseKey: key)
    }()
}
