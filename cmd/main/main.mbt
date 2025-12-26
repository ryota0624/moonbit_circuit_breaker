///|
fn main {
  let settings : @lib.Settings[Unit, String] = @lib.Settings::default()
  let cb = @lib.CircuitBreaker::new(settings)
  println("Circuit Breaker initialized")
  println("Initial state: \{cb.state()}")
}
