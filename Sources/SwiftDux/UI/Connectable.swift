import SwiftUI

/// Makes a view "connectable" to the application state.
@available(iOS 13.0, OSX 10.15, tvOS 13.0, watchOS 6.0, *)
public protocol Connectable {
  associatedtype Superstate
  associatedtype State

  /// Causes the view to be updated based on a dispatched action.
  ///
  /// - Parameter action: The dispatched action
  /// - Returns: True if the view should update.
  func updateWhen(action: Action) -> Bool

  /// Map a superstate to the state needed by the view using the provided parameter.
  ///
  /// The method can return nil until the state becomes available. While it is nil, the view
  /// will not be rendered.
  /// - Parameter state: The superstate provided to the view from a superview.
  /// - Returns: The state if possible.
  func map(state: Superstate) -> State?

  /// Map a superstate to the state needed by the view using the provided parameter.
  ///
  /// The method can return nil until the state becomes available. While it is nil, the view
  /// will not be rendered.
  /// - Parameters:
  ///   - state: The superstate provided to the view from a superview.
  ///   - binder: Helper that creates Binding types beteen the state and a dispatcable action
  /// - Returns: The state if possible.
  func map(state: Superstate, binder: StateBinder) -> State?

}

extension Connectable {

  /// Default implementation disables updates by action.
  public func updateWhen(action: Action) -> Bool {
    action is NoUpdateAction
  }

  /// Default implementation. Returns nil.
  public func map(state: Superstate) -> State? {
    nil
  }

  /// Default implementation. Calls the other map function.
  public func map(state: Superstate, binder: StateBinder) -> State? {
    map(state: state)
  }

}

extension Connectable where Self: View {

  /// Connect the view to the application state
  ///
  /// - Returns: The connected view.
  public func connect() -> some View {
    self.connect(updateWhen: self.updateWhen, mapState: self.map)
  }

}
