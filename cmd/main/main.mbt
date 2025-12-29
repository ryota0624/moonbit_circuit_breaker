///|
async fn main {
  println("=== Circuit Breaker Walkthrough ===")
  println("")

  // 1. Basic initialization with default settings
  println("1. Creating Circuit Breaker with default settings")
  let settings : @lib.Settings[Unit, String] = @lib.Settings::default()
  let cb = @lib.CircuitBreaker::new(settings)
  println("   Initial state: \{cb.state()}")
  println(
    "   Counts - requests: \{cb.counts().requests}, successes: \{cb.counts().total_successes}, failures: \{cb.counts().total_failures}",
  )
  println("")

  // 2. Successful requests in Closed state
  println("2. Executing successful requests (Closed state)")
  for i = 0; i < 3; i = i + 1 {
    let result = cb.run_sync(fn() { Ok(()) })
    println("   Request \{i + 1}: \{result}")
  }
  println("   State: \{cb.state()}")
  println("   Total successes: \{cb.counts().total_successes}")
  println("   Total requests: \{cb.counts().requests}")
  println("")

  // 3. Failed requests that trip the circuit
  println("3. Executing failed requests to trip the circuit")
  println("   (default: consecutive failures > 5)")
  for i = 0; i < 6; i = i + 1 {
    let result = cb.run_sync(fn() -> Result[Unit, String] {
      Err("service unavailable")
    })
    println("   Request \{i + 1}: \{result}")
    println("   Consecutive failures: \{cb.counts().consecutive_failures()}")
  }
  println("   State after failures: \{cb.state()}")
  println("")

  // 4. Demonstrating Open to HalfOpen transition with timeout
  println("4. Demonstrating Open to HalfOpen transition with async sleep")
  println("")
  println("   Current state: \{cb.state()} (Open from step 3)")
  println("   Default timeout: 60 seconds")
  println("")
  println(
    "   To demonstrate the timeout mechanism, we'll wait 2 seconds using sleep_js",
  )
  println("   (In a real scenario, you'd wait for the full timeout period)")
  println("")

  // Wait using sleep_js
  println("   Waiting 2 seconds with @lib.sleep_js...")
  sleep(2000)
  println("   Wait complete! sleep_js successfully executed")
  println("")
  println("   Note: The circuit is still Open because only 2 seconds passed")
  println("   (timeout is 60 seconds by default)")
  println(
    "   After the full timeout, the next request would transition to HalfOpen",
  )
  println("")

  // 5. Demonstrating result handling with map
  println("5. Result handling methods")
  println("   Creating a new circuit breaker for integer results")
  let cb2 = @lib.CircuitBreaker::new(@lib.Settings::default())
  let success_result = cb2.run_sync(fn() { Ok(42) })
  println("   Success result: \{success_result}")
  let mapped = success_result.map(fn(x) { x * 2 })
  println("   Mapped with (*2): \{mapped}")
  let failure_result = cb2.run_sync(fn() -> Result[Int, String] {
    Err("network error")
  })
  println("   Failure result: \{failure_result}")
  let mapped_error = failure_result.map_errors(fn(e) { "App error: \{e}" }, fn(
    _e,
  ) {
    "CB error occurred"
  })
  println("   Failure mapped to string: \{mapped_error}")
  println("")

  // 6. Demonstrating circuit behavior with multiple failures
  println("6. Testing circuit behavior with mixed success/failure patterns")
  let cb3 = @lib.CircuitBreaker::new(@lib.Settings::default())

  // Mix of successes and failures - not enough consecutive failures to trip
  println("   Pattern: S S F F S F (not enough consecutive failures to trip)")
  cb3.run_sync(fn() { Ok(()) }) |> ignore // Success
  cb3.run_sync(fn() { Ok(()) }) |> ignore // Success
  cb3.run_sync(fn() -> Result[Unit, String] { Err("err") }) |> ignore // Failure
  cb3.run_sync(fn() -> Result[Unit, String] { Err("err") }) |> ignore // Failure
  cb3.run_sync(fn() { Ok(()) }) |> ignore // Success - resets consecutive failures
  cb3.run_sync(fn() -> Result[Unit, String] { Err("err") }) |> ignore // Failure
  println("   State after mixed pattern: \{cb3.state()} (still Closed)")
  println("   Consecutive failures: \{cb3.counts().consecutive_failures()}")
  println("")

  // Now trip the circuit with consecutive failures
  println("   Pattern: 6 consecutive failures to trip the circuit")
  for i = 0; i < 6; i = i + 1 {
    cb3.run_sync(fn() -> Result[Unit, String] { Err("error") }) |> ignore
  }
  println("   State after 6 consecutive failures: \{cb3.state()}")
  println("")

  // 7. State transition summary
  println("7. State Transition Summary")
  println("   ┌────────┐")
  println("   │ Closed │ ← Normal operation, requests flow through")
  println("   └────┬───┘")
  println("        │ consecutive failures > threshold")
  println("        ▼")
  println("   ┌────────┐")
  println("   │  Open  │ ← Rejects all requests, protects system")
  println("   └────┬───┘")
  println("        │ after timeout period (60s default)")
  println("        ▼")
  println("   ┌──────────┐")
  println("   │ HalfOpen │ ← Allows limited requests to test recovery")
  println("   └─────┬────┘")
  println("         │")
  println("    ┌────┴─────┐")
  println("    │          │")
  println("success     failure")
  println("    │          │")
  println("    ▼          ▼")
  println(" Closed      Open")
  println("")
  println("8. Async sleep demonstration complete")
  println("   The sleep_js function successfully waits asynchronously")
  println(
    "   This is used internally by the circuit breaker for timeout handling",
  )
  println("")
  println("=== Walkthrough Complete ===")
}

///|
#cfg(target="js")
extern "js" fn js_set_timeout(f : () -> Unit, duration~ : Int) -> Unit =
  #| (f, duration) => setTimeout(f, duration)

///|
#cfg(target="js")
async fn sleep(ms : Int64) -> Unit {
  // FFI implementation using JavaScript's setTimeout
  // This will be replaced with proper async implementation
  let ms_int = ms.to_int()
  suspend(fn(resolve, _reject) {
    js_set_timeout(fn() { resolve(()) }, duration=ms_int)
  })
}

///|
#cfg(target="native")
async fn sleep(ms : Int) -> Unit {
  @async.sleep(ms)
}

///|
/// `suspend` will suspend the execution of the current coroutine.
/// The suspension will be handled by a callback passed to `suspend`
async fn[T, E : Error] suspend(
  // `f` is a callback for handling suspension
  f : (
    // the first parameter of `f` is used to resume the execution of the coroutine normally
    (T) -> Unit,
    // the second parameter of `f` is used to cancel the execution of the current coroutine
    // by throwing an error at suspension point
    (E) -> Unit,
  ) -> Unit,
) -> T raise E = "%async.suspend"
