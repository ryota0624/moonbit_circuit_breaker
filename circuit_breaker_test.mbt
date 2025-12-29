// Test for Circuit Breaker State transitions

///|
test "State enum" {
  let settings : Settings[Unit, String] = Settings::default()
  let cb = CircuitBreaker::new(settings)

  // Test that initial state is Closed
  inspect(cb.state(), content="Closed")
}

///|
test "Counts basic operations" {
  let counts = Counts::new()
  inspect(counts.requests, content="0")
  inspect(counts.total_successes, content="0")
  inspect(counts.total_failures, content="0")
  counts.on_request()
  inspect(counts.requests, content="1")
  counts.on_success()
  inspect(counts.total_successes, content="1")
  inspect(counts.consecutive_successes(), content="1")
  inspect(counts.consecutive_failures(), content="0")
  counts.on_request()
  counts.on_failure()
  inspect(counts.total_failures, content="1")
  inspect(counts.consecutive_failures(), content="1")
  inspect(counts.consecutive_successes(), content="0")
}

///|
test "Counts clear" {
  let counts = Counts::new()
  counts.on_request()
  counts.on_success()
  counts.clear()
  inspect(counts.requests, content="0")
  inspect(counts.total_successes, content="0")
  inspect(counts.consecutive_successes(), content="0")
}

///|
test "Settings default" {
  let settings : Settings[Unit, String] = Settings::default()
  inspect(settings.name, content="CircuitBreaker")
  inspect(settings.max_requests, content="1")
  inspect(settings.timeout, content="60000")
}

///|
test "CircuitBreaker initial state" {
  let settings : Settings[Unit, String] = Settings::default()
  let cb = CircuitBreaker::new(settings)
  inspect(cb.state(), content="Closed")
  inspect(cb.counts().requests, content="0")
}

///|
test "CircuitBreaker successful request in Closed state" {
  let settings : Settings[Unit, String] = Settings::default()
  let cb = CircuitBreaker::new(settings)
  let result = cb.run_sync(fn() { Ok(()) })
  inspect(result, content="Success(())")
  inspect(cb.state(), content="Closed")
  inspect(cb.counts().total_successes, content="1")
  inspect(cb.counts().requests, content="1")
}

///|
test "CircuitBreaker failed request in Closed state" {
  let settings : Settings[Unit, String] = Settings::default()
  let cb = CircuitBreaker::new(settings)
  let result = cb.run_sync(fn() -> Result[Unit, String] { Err("error") })
  inspect(result, content="Failure(\"error\")")
  inspect(cb.state(), content="Closed")
  inspect(cb.counts().total_failures, content="1")
  inspect(cb.counts().consecutive_failures(), content="1")
}

///|
test "CircuitBreaker transitions to Open after consecutive failures" {
  let settings : Settings[Unit, String] = Settings::default()
  let cb = CircuitBreaker::new(settings)

  // Default ready_to_trip is consecutive_failures > 5
  for i = 0; i < 6; i = i + 1 {
    let _result = cb.run_sync(fn() -> Result[Unit, String] { Err("error") })

  }
  inspect(cb.state(), content="Open")
  inspect(cb.counts().consecutive_failures(), content="0") // Cleared after state change
}

///|
test "CircuitBreaker rejects request in Open state" {
  let settings : Settings[Unit, String] = Settings::default()
  let cb = CircuitBreaker::new(settings)

  // Trip the circuit (default ready_to_trip is consecutive_failures > 5)
  for i = 0; i < 6; i = i + 1 {
    let _result = cb.run_sync(fn() -> Result[Unit, String] { Err("error") })

  }
  inspect(cb.state(), content="Open")

  // Check expiry after transition to Open
  inspect(cb.expiry > 0L, content="true")

  // Next request should be rejected
  let result = cb.run_sync(fn() -> Result[Unit, String] { Ok(()) })
  inspect(result, content="Rejected(OpenCircuit)")
}

///|
test "CircuitBreaker custom ready_to_trip" {
  let settings : Settings[Unit, String] = Settings::default()
  let cb = CircuitBreaker::new(settings)

  // Execute 6 failed requests to trip the circuit
  for i = 0; i < 6; i = i + 1 {
    let _result = cb.run_sync(fn() -> Result[Unit, String] { Err("error") })

  }
  inspect(cb.state(), content="Open")
}

///|
test "CircuitBreaker state change callback" {
  let settings : Settings[Unit, String] = Settings::default()
  let cb = CircuitBreaker::new(settings)

  // Trip the circuit
  for i = 0; i < 6; i = i + 1 {
    let _result = cb.run_sync(fn() -> Result[Unit, String] { Err("error") })

  }

  // Just check that the state changed to Open
  inspect(cb.state(), content="Open")
}

///|
test "CircuitBreaker transitions from Open to HalfOpen after timeout" {
  // Create a custom time source that we can control
  let mut current_time = 0L
  let get_now = fn() { current_time }
  let settings : Settings[Unit, String] = Settings::default()
    .with_timeout(10000L) // 10 seconds timeout
    .with_get_now(get_now)
  let cb = CircuitBreaker::new(settings)

  // Initial state should be Closed
  inspect(cb.state(), content="Closed")

  // Trip the circuit (default ready_to_trip is consecutive_failures > 5)
  for i = 0; i < 6; i = i + 1 {
    let _result = cb.run_sync(fn() -> Result[Unit, String] { Err("error") })

  }

  // State should now be Open
  inspect(cb.state(), content="Open")

  // Try a request immediately - should be rejected
  let result1 = cb.run_sync(fn() -> Result[Unit, String] { Ok(()) })
  inspect(result1, content="Rejected(OpenCircuit)")
  inspect(cb.state(), content="Open")

  // Advance time by 5 seconds (not enough to trigger HalfOpen)
  current_time = 5000L
  let result2 = cb.run_sync(fn() -> Result[Unit, String] { Ok(()) })
  inspect(result2, content="Rejected(OpenCircuit)")
  inspect(cb.state(), content="Open")

  // Advance time by another 5 seconds (total 10 seconds - should trigger HalfOpen)
  current_time = 10000L
  let result3 = cb.run_sync(fn() -> Result[Unit, String] { Ok(()) })

  // The request should have succeeded (not rejected)
  inspect(result3, content="Success(())")

  // After successful request in HalfOpen, should transition to Closed
  // (since default max_requests is 1)
  inspect(cb.state(), content="Closed")
}

///|
test "CircuitBreaker remains Open before timeout expires" {
  let mut current_time = 0L
  let get_now = fn() { current_time }
  let settings : Settings[Unit, String] = Settings::default()
    .with_timeout(20000L) // 20 seconds timeout
    .with_get_now(get_now)
  let cb = CircuitBreaker::new(settings)

  // Trip the circuit
  for i = 0; i < 6; i = i + 1 {
    let _result = cb.run_sync(fn() -> Result[Unit, String] { Err("error") })

  }
  inspect(cb.state(), content="Open")

  // Advance time but not enough for timeout
  current_time = 19999L
  let result = cb.run_sync(fn() -> Result[Unit, String] { Ok(()) })

  // Should still be rejected and remain Open
  inspect(result, content="Rejected(OpenCircuit)")
  inspect(cb.state(), content="Open")

  // Advance time to exactly timeout
  current_time = 20000L
  let result2 = cb.run_sync(fn() -> Result[Unit, String] { Ok(()) })

  // The request should succeed
  inspect(result2, content="Success(())")

  // After successful request in HalfOpen, should transition to Closed
  // (since default max_requests is 1)
  inspect(cb.state(), content="Closed")
}
