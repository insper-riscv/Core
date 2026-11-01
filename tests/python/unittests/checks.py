"""Shared helpers for the cocotb tests."""

import logging

_LOG = logging.getLogger("cocotb.tests")


def log_info(message: str) -> None:
    """Log an informational message through the cocotb logger tree."""
    _LOG.info("%s", message)


def check_equal(
    actual: object, expected: object, message: object = ""
) -> None:
    """Raise AssertionError when actual differs from expected.

    The message may be any value (a tuple of the inputs, for example);
    it is only formatted into the failure text.
    """
    if actual != expected:
        raise AssertionError(f"{actual!r} != {expected!r}: {message}")


def check_true(condition: object, message: object = "") -> None:
    """Raise AssertionError when condition is false."""
    if not condition:
        raise AssertionError(message)


def pseudo_random(seed, count, bits):
    """Return count deterministic integers of the given bit width.

    A xorshift64 generator, so the vectors are reproducible without
    pulling in a cryptographically unsuitable `random` generator.
    """
    state = seed or 1
    mask64 = (1 << 64) - 1
    values = []
    for _ in range(count):
        state ^= (state << 13) & mask64
        state ^= state >> 7
        state ^= (state << 17) & mask64
        values.append(state & ((1 << bits) - 1))
    return values


class Prng:
    """Deterministic xorshift64 generator for reproducible stimuli."""

    def __init__(self, seed):
        """Start the sequence from a seed."""
        self.state = (seed & ((1 << 64) - 1)) or 1

    def getrandbits(self, bits):
        """Return an integer of the given bit width."""
        mask64 = (1 << 64) - 1
        self.state ^= (self.state << 13) & mask64
        self.state ^= self.state >> 7
        self.state ^= (self.state << 17) & mask64
        return (self.state >> (64 - bits)) if bits else 0

    def randrange(self, start, stop=None):
        """Return an integer in [start, stop), or [0, start)."""
        if stop is None:
            start, stop = 0, start
        return start + self.getrandbits(32) % (stop - start)

    def randint(self, low, high):
        """Return an integer in [low, high]."""
        return self.randrange(low, high + 1)

    def choice(self, sequence):
        """Return one element of the sequence."""
        return sequence[self.randrange(len(sequence))]
