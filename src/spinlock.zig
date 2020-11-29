pub const SpinLock = struct {
    state: State,

    const State = enum(u8) {
        Unlocked,
        Locked,
    };

    pub const Held = struct {
        spinlock: *SpinLock,

        pub fn release(self: Held) void {
            @atomicStore(State, &self.spinlock.state, .Unlocked, .Release);
        }
    };

    pub fn init() SpinLock {
        return SpinLock{ .state = .Unlocked };
    }

    pub fn deinit(self: *SpinLock) void {
        self.* = undefined;
    }

    pub fn tryAcquire(self: *SpinLock) ?Held {
        return switch (@atomicRmw(State, &self.state, .Xchg, .Locked, .Acquire)) {
            .Unlocked => Held{ .spinlock = self },
            .Locked => null,
        };
    }

    pub fn acquire(self: *SpinLock) Held {
        while (true) {
            return self.tryAcquire() orelse {
                continue;
            };
        }
    }
};
