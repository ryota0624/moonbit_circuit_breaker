///|
extern "js" fn js_date_now_double() -> Double =
  #|() => Date.now()

///|
#cfg(target="js")
fn get_current_time_ms() -> Int64 {
  js_date_now_double().to_int64()
}
