"""Cross-process Windows mutex shared with the PowerShell key maintenance tools."""
from contextlib import contextmanager
import ctypes
from ctypes import wintypes
import os


@contextmanager
def key_lock():
    if os.name != 'nt':
        raise OSError('Host key-store maintenance requires Windows')
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.CreateMutexW.argtypes = [wintypes.LPVOID, wintypes.BOOL, wintypes.LPCWSTR]
    kernel.CreateMutexW.restype = wintypes.HANDLE
    kernel.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
    kernel.WaitForSingleObject.restype = wintypes.DWORD
    kernel.ReleaseMutex.argtypes = [wintypes.HANDLE]
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    mutex = kernel.CreateMutexW(None, False, 'Global\\QrPowerShellConnect-Keys')
    if not mutex:
        raise ctypes.WinError(ctypes.get_last_error())
    acquired = False
    try:
        result = kernel.WaitForSingleObject(mutex, 10000)
        acquired = result in (0, 0x80)
        if not acquired:
            raise TimeoutError('Another key-store operation is running; retry later')
        yield
    finally:
        if acquired:
            kernel.ReleaseMutex(mutex)
        kernel.CloseHandle(mutex)
