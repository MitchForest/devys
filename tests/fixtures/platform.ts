/** Unit-test host only; runtime integration tests use real workerd classes. */
export class DurableObject<Env> {
  constructor(
    protected ctx: DurableObjectState,
    protected env: Env,
  ) {}
}
export class WorkerEntrypoint<Env> {
  constructor(
    protected ctx: ExecutionContext,
    protected env: Env,
  ) {}
}
