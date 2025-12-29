---
moonbit:
  backend:
    js
---

# ryota0624/circuit_breaker_mbt

A circuit breaker implementation for MoonBit inspired by https://github.com/sony/gobreaker

## supported backends

- js
- native

## Overview

Circuit Breaker is a design pattern used to detect failures and prevent cascading failures in distributed systems. This implementation provides three states:

- **Closed**: Normal operation, requests pass through
- **Open**: Too many failures detected, requests are rejected immediately
- **HalfOpen**: Testing if the system has recovered, limited requests allowed

## Basic Usage

```mbt check
test "basic circuit breaker usage" {
  // Create a circuit breaker with default settings
  let settings : @ryota0624/circuit_breaker.Settings[Int, String] = 
    @ryota0624/circuit_breaker.Settings::default()
  
  let cb = @ryota0624/circuit_breaker.CircuitBreaker::new(settings)
  
  // Execute a function through the circuit breaker
  let result = cb.run_sync(fn() -> Result[Int, String] { 
    Ok(42) 
  })
  
  inspect(result, content="Success(42)")
}
```

## Custom Configuration

```mbt check
test "custom circuit breaker configuration" {
  let mut current_time = 0L
  
  let settings : @ryota0624/circuit_breaker.Settings[Int, String] = 
    @ryota0624/circuit_breaker.Settings::default()
      .with_name("MyService")
      .with_timeout(5000L)        // 5 seconds timeout in Open state
      .with_max_requests(3L)      // Allow 3 requests in HalfOpen state
      .with_get_now(fn() { current_time })  // Custom time source for testing
  
  let cb = @ryota0624/circuit_breaker.CircuitBreaker::new(settings)
  
  // Simulate failures to trip the circuit
  for i = 0; i < 6; i = i + 1 {
    let _ = cb.run_sync(fn() -> Result[Int, String] { 
      Err("service unavailable") 
    })
  }
  
  // Circuit should be open now
  inspect(cb.state(), content="Open")
  
  // Requests are rejected in Open state
  let result = cb.run_sync(fn() -> Result[Int, String] { Ok(1) })
  inspect(result, content="Rejected(OpenCircuit)")
  
  // Advance time past timeout
  current_time = 5000L
  
  // Circuit transitions to HalfOpen and allows request
  let result2 = cb.run_sync(fn() -> Result[Int, String] { Ok(1) })
  inspect(result2, content="Success(1)")
}
```

## Error Handling

```mbt check
test "error handling with circuit breaker" {
  let settings : @ryota0624/circuit_breaker.Settings[String, String] = 
    @ryota0624/circuit_breaker.Settings::default()
  
  let cb = @ryota0624/circuit_breaker.CircuitBreaker::new(settings)
  
  // Handle different result types
  let result = cb.run_sync(fn() -> Result[String, String] { 
    Err("error") 
  })
  
  inspect(result, content="Failure(\"error\")")
}
```
