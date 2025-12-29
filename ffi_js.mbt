///|
#cfg(target="js")
extern "js" fn js_date_now() -> Int64 =
  #| () => Date.now()

///|
fn get_current_time_ms() -> Int64 {
  js_date_now()
}
