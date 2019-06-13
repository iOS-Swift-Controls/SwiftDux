import Foundation

/// Storage for the ordered state to decrease the copying of the internal data structures.
fileprivate class OrderedStateStorage<Id, Substate>: Codable, Equatable where Substate: IdentifiableState, Id == Substate.Id  {
  enum CodingKeys: String, CodingKey {
    case orderOfIds
    case values
  }
  
  /// Holds the oredering knowledge of the values by their key.
  var orderOfIds: [Id]
  
  /// Holds the actual value referenced by its key.
  var values: Dictionary<Id, Substate>
  
  /// For the usage of ordered enumerations, this property caches a reverse lookup table from key to ordered position.
  var cachedIdsByOrder: [Id: Int]?
  
  /// Sets the initial values and their ordered positions.
  ///
  /// This class assumes that the data in both `orderOfIds` and `values` are perfectly synced.
  init(orderOfIds: [Id], values: [Id: Substate]) {
    self.orderOfIds = orderOfIds
    self.values = values
    self.cachedIdsByOrder = nil
  }
  
  static func == (lhs: OrderedStateStorage<Id, Substate>, rhs: OrderedStateStorage<Id, Substate>) -> Bool {
    return lhs.orderOfIds == rhs.orderOfIds && lhs.values == lhs.values
  }
  
  /// Returns the ordered index position of a key.
  ///
  /// This method assumes it will be called multiple times in succession, so it internally caches
  /// the indexes by their keys in a reverse lookup table.
  ///
  /// - Parameter id: The key to look  up its ordered index position
  /// - Returns: An ordered
  func index(ofId id: Id) -> Int {
    if cachedIdsByOrder == nil {
      self.cachedIdsByOrder = Dictionary<Id, Int>(
        uniqueKeysWithValues: orderOfIds.enumerated().map { (index, id) in (id, index) }
      )
    }
    return self.cachedIdsByOrder![id]!
  }
  
  /// Invalidates the caches. This should be called when it's assumed that the order of keys may change.
  func invalidateCache() {
    self.cachedIdsByOrder = nil
  }

}

/// A container state that holds an ordered collection of substates.
///
/// It's a common requirement to store a collection of substates. For example, a list of entities retrieved from a service.
/// For an optimal solution, you typically require a lookup table of entity states by their ids. However, you also need an ordered array
/// to display those entities in a list to the user. You end up managing both a dictionary of users and an ordered array of their ids.
/// This class manages this responsibility for you. It also provides conveniences for use by the `List` type views in SwiftUI.
///
/// struct AppState {
///   todos: OrderedState<TodoState>
/// }
///
/// // When a user adds a new todo:
/// todos.append(todo)
///
/// // When a user deletes from a `List` view, simply pass in the provided `IndexSet`:
/// todos.delete(at: indexSet)
///
public struct OrderedState<Id, Substate>: StateType where Substate: IdentifiableState, Id == Substate.Id {
  
  fileprivate var storage: OrderedStateStorage<Id, Substate>
  
  /// An ordered array of the substates.
  public var values: [Substate] {
    return storage.orderOfIds.map { storage.values[$0]! }
  }
  
  /// The number of substates
  public var count: Int {
    return storage.orderOfIds.count
  }
  
  /// Used for internal copy operations.
  private init(orderOfIds: [Id], values: [Id:Substate]) {
    self.storage = OrderedStateStorage(
      orderOfIds: orderOfIds,
      values: values
    )
  }
  
  /// Create a new `OrderedState` with an ordered array of identifiable substates.
  public init(_ values: [Substate]) {
    var valueByIndex = [Id:Substate](minimumCapacity: values.count)
    let orderOfIds: [Id] = values.map {
      valueByIndex[$0.id] = $0
      return $0.id
    }
    self.init(orderOfIds: orderOfIds, values: valueByIndex)
  }
  
  /// Create a new `OrderedState` with a variadic number of substates.
  public init(_ value: Substate...) {
    self.init(value)
  }
  
  /// Used internally to copy the storage for mutating operations. It's designed not to
  /// copy if it's singularily owned by a single copy of the `OrderedState` struct.
  private mutating func copyStorageIfNeeded() -> OrderedStateStorage<Id, Substate> {
    guard isKnownUniquelyReferenced(&storage) else {
      return OrderedStateStorage(orderOfIds: storage.orderOfIds, values: storage.values)
    }
    storage.invalidateCache()
    return storage
  }
  
  /// Append a new substate to the end of the `OrderedState`.
  public mutating func append(_ value: Substate) {
    self.insert(value, at: storage.orderOfIds.count)
  }
  
  /// Prepend a new substate to the beginning of the `OrderedState`.
  public mutating func prepend(_ value: Substate) {
    self.insert(value, at: 0)
  }
  
  /// Inserts a new substate at the given index `OrderedState`.
  public mutating func insert(_ value: Substate, at index: Int) {
    let copy = copyStorageIfNeeded()
    if copy.orderOfIds.count != copy.values.count {
      fatalError("Counts don't match!")
    }
    copy.orderOfIds.insert(value.id, at: index)
    copy.values[value.id] = value
    self.storage = copy
  }
  
  /// Inserts a collection of substates at the given index.
  public mutating func insert<C>(contentsOf values: C, at index: Int) where C: Collection, C.Element == Substate {
    let copy = copyStorageIfNeeded()
    let ids = values.map { value -> Id in
      copy.values[value.id] = value
      return value.id
    }
    copy.orderOfIds.insert(contentsOf: ids, at: index)
    self.storage = copy
  }
  
  /// Removes a substate for the given id.
  public mutating func remove(forId id: Id) {
    let copy = copyStorageIfNeeded()
    if copy.values.removeValue(forKey: id) != nil {
      copy.orderOfIds.removeAll { $0 == id }
    }
    self.storage = copy
  }
  
  /// Removes a substate at a given index.
  public mutating func remove(at index: Int) {
    let copy = copyStorageIfNeeded()
    copy.values.removeValue(forKey: copy.orderOfIds[index])
    copy.orderOfIds.remove(at: index)
    self.storage = copy
  }
  
  /// Removes substates at the provided indexes.
  public mutating func remove(at indexSet: IndexSet) {
    let copy = copyStorageIfNeeded()
    indexSet.forEach { copy.values.removeValue(forKey: copy.orderOfIds[$0]) }
    copy.orderOfIds.remove(at:  indexSet)
    self.storage = copy
  }
  
  /// Moves a set of substates at the specified indexes to a new index position.
  public mutating func move(from indexSet: IndexSet, to index: Int) {
    let copy = copyStorageIfNeeded()
    let currentIdAtIndex = copy.orderOfIds[index]
    let ids = Array(indexSet.map { copy.orderOfIds[$0] })
    copy.orderOfIds.remove(at: indexSet)
    copy.orderOfIds.insert(contentsOf: ids, at: copy.index(ofId: currentIdAtIndex) + 1)
    self.storage = copy
  }
  
  /// Resorts the order of substates with the given sort operation.
  /// - Parameter areInIncreasingOrder: Orders the items by indicating whether not the second item is bigger than the first item.
  public mutating func sort(by areInIncreasingOrder: (Substate, Substate) -> Bool) {
    let copy = copyStorageIfNeeded()
    copy.orderOfIds.sort { areInIncreasingOrder(copy.values[$0]!, copy.values[$1]!) }
    self.storage = copy
  }
  
  /// - Parameter areInIncreasingOrder: Orders the items by indicating whether not the second item is bigger than the first item.
  /// - Returns: A new `OrderedState` with the provided sort operation.
  public func sorted(by operation: (Substate, Substate) -> Bool) -> Self {
    let orderOfIds = storage.orderOfIds.sorted { operation(storage.values[$0]!, storage.values[$1]!) }
    return OrderedState(orderOfIds: orderOfIds, values: storage.values)
  }
  
  /// - Returns: an array of substates filtered by the provided operation.
  public func filter(_ isIncluded: (Substate) -> Bool) -> [Substate] {
    return storage.orderOfIds.compactMap { id -> Substate? in
      let value = storage.values[id]!
      return isIncluded(value) ? value : nil
    }
  }
  
}

extension OrderedState: MutableCollection {
  
  public var startIndex: Id {
    return storage.orderOfIds.first!
  }
  
  public var endIndex: Id {
    return storage.orderOfIds.last!
  }
  
  public subscript(position: Id) -> Substate {
    get {
      return storage.values[position]!
    }
    set(newValue) {
      let copy = copyStorageIfNeeded()
      let alreadyExists = copy.values.index(forKey: position) != nil
      copy.values[position] = newValue
      if !alreadyExists {
        copy.orderOfIds.append(position)
      }
      self.storage = copy
    }
  }
  
  public __consuming func makeIterator() -> IndexingIterator<Array<Substate>> {
    return self.values.makeIterator()
  }
  
  public func index(after i: Id) -> Id {
    let index = storage.index(ofId: i)
    return storage.orderOfIds[index + 1]
  }
  
}

extension RangeReplaceableCollection where Self: MutableCollection, Index == Int {
  
  // Nifty optimization from user vadian at: https://stackoverflow.com/a/50835467
  
  public mutating func remove(at indexes: IndexSet) {
    guard var i = indexes.first, i < count else { return }
    var j = index(after: i)
    var k = indexes.integerGreaterThan(i) ?? endIndex
    while j != endIndex {
      if k != j { swapAt(i, j); formIndex(after: &i) }
      else { k = indexes.integerGreaterThan(k) ?? endIndex }
      formIndex(after: &j)
    }
    removeSubrange(i...)
  }
}

extension OrderedState: Equatable {
  
  public static func == (lhs: OrderedState<Id, Substate>, rhs: OrderedState<Id, Substate>) -> Bool {
    return lhs.storage == rhs.storage
  }
  
}