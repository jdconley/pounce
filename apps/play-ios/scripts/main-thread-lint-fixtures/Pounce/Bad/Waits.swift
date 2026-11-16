// expect: thread-sleep, c-sleep, semaphore, wait-call, sync-dispatch, lock, mutex, run-loop-run, defaults-synchronize
import Foundation
import Synchronization
@MainActor func block() {
    Thread.sleep(forTimeInterval: 0.1)
    usleep(1000)
    let s = DispatchSemaphore(value: 0)
    _ = DispatchGroup().wait(timeout: .now() + 1)
    DispatchQueue.global().sync { }
    let lock = NSLock()
    let m = Mutex(0)
    RunLoop.current.run(until: .now)
    UserDefaults.standard.synchronize()
    _ = (s, lock, m)
}
