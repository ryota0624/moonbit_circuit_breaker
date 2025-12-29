// Circuit Breaker State

///|
pub(all) enum State {
  Closed
  Open
  HalfOpen
} derive(Eq, Show)

// ConsecutiveResult represents consecutive successes or failures

///|
pub enum ConsecutiveResult {
  Successes(Int64)
  Failures(Int64)
} derive(Eq, Show)

// Counts holds the numbers of requests and their successes/failures

///|
pub struct Counts {
  mut requests : Int64
  mut total_successes : Int64
  mut total_failures : Int64
  mut consecutive : ConsecutiveResult
}

///|
pub fn Counts::new() -> Counts {
  {
    requests: 0L,
    total_successes: 0L,
    total_failures: 0L,
    consecutive: Successes(0L),
  }
}

///|
pub fn Counts::on_request(self : Counts) -> Unit {
  self.requests += 1L
}

///|
pub fn Counts::on_success(self : Counts) -> Unit {
  self.total_successes += 1L
  self.consecutive = match self.consecutive {
    Successes(n) => Successes(n + 1L)
    Failures(_) => Successes(1L)
  }
}

///|
pub fn Counts::on_failure(self : Counts) -> Unit {
  self.total_failures += 1L
  self.consecutive = match self.consecutive {
    Failures(n) => Failures(n + 1L)
    Successes(_) => Failures(1L)
  }
}

///|
pub fn Counts::clear(self : Counts) -> Unit {
  self.requests = 0L
  self.total_successes = 0L
  self.total_failures = 0L
  self.consecutive = Successes(0L)
}

// Helper methods to get consecutive counts

///|
pub fn Counts::consecutive_successes(self : Counts) -> Int64 {
  match self.consecutive {
    Successes(n) => n
    Failures(_) => 0L
  }
}

///|
pub fn Counts::consecutive_failures(self : Counts) -> Int64 {
  match self.consecutive {
    Failures(n) => n
    Successes(_) => 0L
  }
}

// Settings configures CircuitBreaker

///|
pub struct Settings[T, E] {
  name : String
  max_requests : Int64 // Maximum number of requests allowed in HalfOpen state
  interval : Int64 // Period in milliseconds to clear counts in Closed state
  timeout : Int64 // Period in milliseconds after which Open state transitions to HalfOpen
  ready_to_trip : (Counts) -> Bool // Function to determine if circuit should trip
  on_state_change : (String, State, State) -> Unit // Callback on state change
  is_successful : (Result[T, E]) -> Bool // Function to determine if result is successful
  get_now : () -> Int64 // Function to get current time in milliseconds
}

///|
pub fn[T, E] Settings::default() -> Settings[T, E] {
  {
    name: "CircuitBreaker",
    max_requests: 1L,
    interval: 0L,
    timeout: 60000L, // 60 seconds
    ready_to_trip: fn(counts) { counts.consecutive_failures() > 5L },
    on_state_change: fn(_name, _from, _to) { () },
    is_successful: fn(result) {
      match result {
        Ok(_) => true
        Err(_) => false
      }
    },
    get_now: fn() { get_current_time_ms() },
  }
}

///|
pub fn[T, E] Settings::with_name(
  self : Settings[T, E],
  name : String,
) -> Settings[T, E] {
  { ..self, name, }
}

///|
pub fn[T, E] Settings::with_max_requests(
  self : Settings[T, E],
  max_requests : Int64,
) -> Settings[T, E] {
  { ..self, max_requests, }
}

///|
pub fn[T, E] Settings::with_interval(
  self : Settings[T, E],
  interval : Int64,
) -> Settings[T, E] {
  { ..self, interval, }
}

///|
pub fn[T, E] Settings::with_timeout(
  self : Settings[T, E],
  timeout : Int64,
) -> Settings[T, E] {
  { ..self, timeout, }
}

///|
pub fn[T, E] Settings::with_get_now(
  self : Settings[T, E],
  get_now : () -> Int64,
) -> Settings[T, E] {
  { ..self, get_now, }
}

// CircuitBreaker is a state machine to prevent sending requests that are likely to fail

///|
pub struct CircuitBreaker[T, E] {
  settings : Settings[T, E]
  mut state : State
  mut generation : Int64
  counts : Counts
  mut expiry : Int64 // Timestamp in milliseconds
  get_now : () -> Int64 // Function to get current time in milliseconds
}

///|
pub fn[T, E] CircuitBreaker::new(
  settings : Settings[T, E],
) -> CircuitBreaker[T, E] {
  let now = (settings.get_now)()
  let mut expiry = 0L
  if settings.interval > 0L {
    expiry = now + settings.interval
  }
  {
    settings,
    state: Closed,
    generation: 0L,
    counts: Counts::new(),
    expiry,
    get_now: settings.get_now,
  }
}

///|
fn[T, E] CircuitBreaker::get_now(self : CircuitBreaker[T, E]) -> Int64 {
  (self.get_now)()
}

// Get current time in milliseconds (JS backend)
// For now, return 0 as a placeholder since FFI setup is complex

///|
pub fn[T, E] CircuitBreaker::state(self : CircuitBreaker[T, E]) -> State {
  self.state
}

///|
pub fn[T, E] CircuitBreaker::counts(self : CircuitBreaker[T, E]) -> Counts {
  self.counts
}

// CircuitBreakerError represents errors returned by CircuitBreaker

///|
pub suberror CircuitBreakerError {
  TooManyRequests
  OpenCircuit
} derive(Show)

// CircuitBreakerRunResult represents the result of running a function through the CircuitBreaker

///|
pub enum CircuitBreakerRunResult[T, E] {
  Success(T)
  Failure(E)
  Rejected(CircuitBreakerError)
} derive(Show)

///|
fn[T, E] CircuitBreakerRunResult::from_result(
  result : Result[Result[T, E], CircuitBreakerError],
) -> CircuitBreakerRunResult[T, E] {
  match result {
    Ok(value) =>
      match value {
        Ok(v) => Success(v)
        Err(err) => Failure(err)
      }
    Err(err) => Rejected(err)
  }
}

///|
pub fn[T, E : Error] CircuitBreakerRunResult::unwrap_or_error(
  self : CircuitBreakerRunResult[T, E],
) -> T raise {
  match self {
    Success(v) => v
    Failure(err) => raise err
    Rejected(err) => raise err
  }
}

///|
pub fn[T, E, U] CircuitBreakerRunResult::map(
  self : CircuitBreakerRunResult[T, E],
  f : (T) -> U,
) -> CircuitBreakerRunResult[U, E] {
  match self {
    Success(v) => Success(f(v))
    Failure(err) => Failure(err)
    Rejected(err) => Rejected(err)
  }
}

///|
pub fn[T, E, U] CircuitBreakerRunResult::map_errors(
  self : CircuitBreakerRunResult[T, E],
  map_failure : (E) -> U,
  map_rejected : (CircuitBreakerError) -> U,
) -> Result[T, U] {
  match self {
    Success(v) => Ok(v)
    Failure(err) => map_failure(err) |> Err
    Rejected(err) => map_rejected(err) |> Err
  }
}

// Execute runs the given function if the CircuitBreaker accepts it

///|
pub fn[T, E] CircuitBreaker::run_sync(
  self : CircuitBreaker[T, E],
  f : () -> Result[T, E],
) -> CircuitBreakerRunResult[T, E] {
  self
  .before_request()
  .map(fn(generation) {
    let result = f()
    let is_success = (self.settings.is_successful)(result)
    self.after_request(generation, is_success)
    result
  })
  |> CircuitBreakerRunResult::from_result
}

///|
pub fn[T, E : Error] CircuitBreaker::try_sync(
  self : CircuitBreaker[T, E],
  f : () -> T raise E,
) -> T raise {
  self.run_sync(fn() { try? f() }).unwrap_or_error()
}

///|
pub async fn[T, E] CircuitBreaker::run_async(
  self : CircuitBreaker[T, E],
  f : async () -> Result[T, E] noraise,
) -> CircuitBreakerRunResult[T, E] noraise {
  match self.before_request() {
    Err(e) => Rejected(e)
    Ok(generation) => {
      let result = f()
      let is_success = (self.settings.is_successful)(result)
      self.after_request(generation, is_success)
      match result {
        Ok(v) => Success(v)
        Err(err) => Failure(err)
      }
    }
  }
}

///|
pub async fn[T, E : Error] CircuitBreaker::try_async(
  self : CircuitBreaker[T, E],
  f : async () -> T raise E,
) -> T {
  self
  .run_async(async fn() -> Result[T, E] noraise { try? f() })
  .unwrap_or_error()
}

///|
fn[T, E] CircuitBreaker::state_transition_on_before_request(
  self : CircuitBreaker[T, E],
  now : Int64,
) -> Unit {
  match self.state {
    Open =>
      // Check if we need to transition from Open to HalfOpen
      if self.expiry <= now {
        self.change_state(HalfOpen, now)
      }
    HalfOpen => ()
    Closed =>
      // Check if interval has passed in Closed state
      if self.settings.interval > 0L && self.expiry <= now {
        self.to_new_generation(now)
      }
  }
}

///|
fn[T, E] CircuitBreaker::before_request(
  self : CircuitBreaker[T, E],
) -> Result[Int64, CircuitBreakerError] {
  let now = self.get_now()
  self.state_transition_on_before_request(now)
  let generation = self.generation
  let result = match self.state {
    Open => Err(CircuitBreakerError::OpenCircuit)
    HalfOpen =>
      if self.counts.requests >= self.settings.max_requests {
        CircuitBreakerError::TooManyRequests |> Err
      } else {
        Ok(generation)
      }
    Closed => Ok(generation)
  }
  if result is Ok(_) {
    self.counts.on_request()
  }
  result
}

///|
fn[T, E] CircuitBreaker::after_request(
  self : CircuitBreaker[T, E],
  before : Int64,
  success : Bool,
) -> Unit {
  let now = self.get_now()
  let state = self.state

  // Ignore if generation has changed
  if before != self.generation {
    return
  }
  if success {
    self.on_success(state, now)
  } else {
    self.on_failure(state, now)
  }
}

///|
fn[T, E] CircuitBreaker::on_success(
  self : CircuitBreaker[T, E],
  state : State,
  now : Int64,
) -> Unit {
  self.counts.on_success()
  match state {
    Closed => ()
    HalfOpen =>
      if self.counts.consecutive_successes() >= self.settings.max_requests {
        self.change_state(Closed, now)
      }
    Open => ()
  }
}

///|
fn[T, E] CircuitBreaker::on_failure(
  self : CircuitBreaker[T, E],
  state : State,
  now : Int64,
) -> Unit {
  self.counts.on_failure()
  match state {
    Closed =>
      if (self.settings.ready_to_trip)(self.counts) {
        self.change_state(Open, now)
      }
    HalfOpen => self.change_state(Open, now)
    Open => ()
  }
}

///|
fn[T, E] CircuitBreaker::change_state(
  self : CircuitBreaker[T, E],
  new_state : State,
  now : Int64,
) -> Unit {
  if self.state == new_state {
    return
  }
  let prev = self.state
  self.state = new_state
  self.to_new_generation(now)
  (self.settings.on_state_change)(self.settings.name, prev, new_state)
}

///|
fn[T, E] CircuitBreaker::to_new_generation(
  self : CircuitBreaker[T, E],
  now : Int64,
) -> Unit {
  self.generation += 1L
  self.counts.clear()
  match self.state {
    Closed =>
      if self.settings.interval > 0L {
        self.expiry = now + self.settings.interval
      } else {
        self.expiry = 0L
      }
    Open => self.expiry = now + self.settings.timeout
    HalfOpen => self.expiry = 0L
  }
}
