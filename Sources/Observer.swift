//
//  The MIT License (MIT)
//
//  Copyright (c) 2016 Srdan Rasic (@srdanrasic)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

/// Represents a type that receives events.
public typealias Observer<X, Error: Swift.Error> = (Event<X, Error>) -> Void

/// Represents a type that receives events.
public protocol ObserverProtocol {

  /// Type of Xs being received.
  associatedtype X

  /// Type of error that can be received.
  associatedtype Error: Swift.Error

  /// Send the event to the observer.
  func on(_ event: Event<X, Error>)
}

/// Represents a type that receives events. Observer is just a convenience
/// wrapper around a closure observer `Observer<X, Error>`.
public struct AnyObserver<X, Error: Swift.Error>: ObserverProtocol {

  private let observer: Observer<X, Error>

  /// Creates an observer that wraps a closure observer.
  public init(observer: @escaping Observer<X, Error>) {
    self.observer = observer
  }

  /// Calles wrapped closure with the given X.
  public func on(_ event: Event<X, Error>) {
    observer(event)
  }
}

/// Observer that ensures events are sent atomically.
public class AtomicObserver<X, Error: Swift.Error>: ObserverProtocol {

  private let observer: Observer<X, Error>
  private let disposable: Disposable
  private let lock = NSRecursiveLock(name: "com.reactivekit.signal.atomicobserver")
  private var terminated = false

  /// Creates an observer that wraps given closure.
  public init(disposable: Disposable, observer: @escaping Observer<X, Error>) {
    self.disposable = disposable
    self.observer = observer
  }

  /// Calles wrapped closure with the given X.
  public func on(_ event: Event<X, Error>) {
    lock.lock(); defer { lock.unlock() }
    guard !disposable.isDisposed && !terminated else { return }
    if event.isTerminal {
      terminated = true
      observer(event)
      disposable.dispose()
    } else {
      observer(event)
    }
  }
}

// MARK: - Extensions

public extension ObserverProtocol {

  /// Convenience method to send `.next` event.
  public func next(_ X: X) {
    on(.next(X))
  }

  /// Convenience method to send `.failed` event.
  public func failed(_ error: Error) {
    on(.failed(error))
  }

  /// Convenience method to send `.completed` event.
  public func completed() {
    on(.completed)
  }

  /// Convenience method to send `.next` event followed by a `.completed` event.
  public func completed(with X: X) {
    next(X)
    completed()
  }

  /// Converts the receiver to the Observer closure.
  public func toObserver() -> Observer<X, Error> {
    return on
  }
}
