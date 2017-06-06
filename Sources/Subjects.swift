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

/// A type that is both a signal and an observer.
public protocol SubjectProtocol: SignalProtocol, ObserverProtocol {
}

/// A type that is both a signal and an observer.
open class Subject<X, Error: Swift.Error>: SubjectProtocol {

  private typealias Token = Int64
  private var nextToken: Token = 0

  private var observers: [Token: Observer<X, Error>] = [:]
  private var terminated = false

  public let lock = NSRecursiveLock(name: "com.reactivekit.subject")
  public let disposeBag = DisposeBag()

  public init() {}

  public func on(_ event: Event<X, Error>) {
    lock.lock(); defer { lock.unlock() }
    guard !terminated else { return }
    terminated = event.isTerminal
    send(event)
  }

  open func send(_ event: Event<X, Error>) {
    forEachObserver { $0(event) }
  }

  open func observe(with observer: @escaping Observer<X, Error>) -> Disposable {
    lock.lock(); defer { lock.unlock() }
    willAdd(observer: observer)
    return add(observer: observer)
  }

  open func willAdd(observer: @escaping Observer<X, Error>) {
  }

  private func add(observer: @escaping Observer<X, Error>) -> Disposable {
    let token = nextToken
    nextToken = nextToken + 1

    observers[token] = observer

    return BlockDisposable { [weak self] in
      let _ = self?.observers.removeValue(forKey: token)
    }
  }

  private func forEachObserver(_ execute: (Observer<X, Error>) -> Void) {
    for (_, observer) in observers {
      execute(observer)
    }
  }
}

extension Subject: BindableProtocol {

  public func bind(signal: Signal<X, NoError>) -> Disposable {
    return signal
      .take(until: disposeBag.deallocated)
      .observeIn(.nonRecursive())
      .observeNext { [weak self] X in
        guard let s = self else { return }
        s.on(.next(X))
    }
  }
}

/// A subject that propagates received events to the registered observes.
public final class PublishSubject<X, Error: Swift.Error>: Subject<X, Error> {}

/// A subject that replies accumulated sequence of events to each observer.
public final class ReplaySubject<X, Error: Swift.Error>: Subject<X, Error> {

  private var buffer: ArraySlice<Event<X, Error>> = []
  public let bufferSize: Int

  public init(bufferSize: Int = Int.max) {
    if bufferSize < Int.max {
      self.bufferSize = bufferSize + 1 // plus terminal event
    } else {
      self.bufferSize = bufferSize
    }
  }

  public override func send(_ event: Event<X, Error>) {
    buffer.append(event)
    buffer = buffer.suffix(bufferSize)
    super.send(event)
  }

  public override func willAdd(observer: @escaping Observer<X, Error>) {
    buffer.forEach(observer)
  }
}

/// A subject that replies latest event to each observer.
public final class ReplayOneSubject<X, Error: Swift.Error>: Subject<X, Error> {

  private var lastEvent: Event<X, Error>? = nil
  private var terminalEvent: Event<X, Error>? = nil

  public override func send(_ event: Event<X, Error>) {
    if event.isTerminal {
      terminalEvent = event
    } else {
      lastEvent = event
    }
    super.send(event)
  }

  public override func willAdd(observer: @escaping Observer<X, Error>) {
    if let event = lastEvent {
      observer(event)
    }
    if let event = terminalEvent {
      observer(event)
    }
  }
}


@available(*, deprecated, message: "All subjects now inherit 'Subject' that can be used in place of 'AnySubject'.")
public final class AnySubject<X, Error: Swift.Error>: SubjectProtocol {
  private let baseObserve: (@escaping Observer<X, Error>) -> Disposable
  private let baseOn: Observer<X, Error>

  public let disposeBag = DisposeBag()

  public init<S: SubjectProtocol>(base: S) where S.X == X, S.Error == Error {
    baseObserve = base.observe
    baseOn = base.on
  }

  public func on(_ event: Event<X, Error>) {
    return baseOn(event)
  }

  public func observe(with observer: @escaping Observer<X, Error>) -> Disposable {
    return baseObserve(observer)
  }
}
