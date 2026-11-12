use serde_json::{json, Value};
pub fn id(n: usize) -> String {
    format!("00000000-0000-4000-8000-{n:012x}")
}
pub fn definition() -> Value {
    json!({"schema_version":1,"id":id(900),"name":"Original","enabled":false,"conditions":{"id":id(1),"expression":{"type":"all","children":[{"id":id(2),"expression":{"type":"predicate","predicate":{"field":"name","op":"contains","value":"invoice","scope":"filename","case_sensitive":false}}}]}},"actions":[{"id":id(100),"action":{"type":"rename","rename":{"mode":"template","template":{"text":"{stem}","capture_condition_id":null}},"preserve_extension":true}}],"behavior":"stop"})
}
