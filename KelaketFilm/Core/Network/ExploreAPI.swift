import Foundation

// Browse routes (phase 3): archive, actors, box office, schedule and lists.
extension APIClient {
    func searchTerms() async throws -> SearchTerms {
        try await send(Endpoint(path: "mobile/v1/searchTerms"))
    }

    func genres() async throws -> [Genre] {
        let result: LossyArray<Genre> = try await send(Endpoint(path: "mobile/v1/fetchGenres"))
        return result.wrappedValue
    }

    func archive(_ filter: ArchiveFilter, page: Int) async throws -> ArchivePage {
        var query = filter.query
        query["page"] = String(page)
        return try await send(Endpoint(path: "mobile/v2/archive", query: query))
    }

    // MARK: Actors

    /// Every post an actor appears in, newest first.
    func actorWorks(actorId: Int) async throws -> [Post] {
        let result: LossyArray<Post> = try await send(Endpoint(path: "mobile/v2/actorWorks/\(actorId)"))
        return result.wrappedValue
    }

    func actors(search: String, page: Int) async throws -> ActorsPage {
        try await send(Endpoint(path: "mobile/v2/actors/archive",
                                query: ["search": search, "page": String(page), "per_page": "30"]))
    }

    // MARK: Charts

    func boxOffice() async throws -> BoxOffice {
        try await send(Endpoint(path: "mobile/v2/get_boxoffice"))
    }

    /// `day` is a key of the theme's `series_tabbed` option. Days without
    /// series answer with an error object, which decodes as an empty list.
    func weeklySeries(day: String) async throws -> [WeeklySeries] {
        let result: LossyArray<WeeklySeries> = try await send(Endpoint(path: "mobile/v1/getWeeklySeries/\(day)"))
        return result.wrappedValue
    }

    /// `list` is "movies" or "series"; 42 titles per page.
    func top250(list: String, page: Int) async throws -> RankedPage {
        try await send(Endpoint(path: "mobile/v2/lists/top250",
                                query: ["list": list, "page": String(page)]))
    }

    func collections(page: Int) async throws -> CollectionsPage {
        try await send(Endpoint(path: "mobile/v2/lists/collections", query: ["page": String(page)]))
    }

    // MARK: User lists

    func myLists() async throws -> [UserList] {
        try await send(Endpoint(path: "mobile/v2/lists/my"), as: UserListsPage.self).lists
    }

    func publicLists(page: Int) async throws -> UserListsPage {
        try await send(Endpoint(path: "mobile/v2/lists/public",
                                query: ["page": String(page), "limit": "10"]))
    }

    /// The name must be at least 6 characters; the server says so otherwise.
    func createList(name: String, description: String, isPrivate: Bool, films: [Int]) async throws {
        _ = try await send(Endpoint(path: "mobile/v2/lists/create", method: .post,
                                    body: ListBody(listId: nil, name: name, listDesc: description,
                                                   isPrivate: isPrivate, films: films)),
                           as: IgnoredResponse.self)
    }

    func updateList(id: Int, name: String, description: String, isPrivate: Bool) async throws {
        _ = try await send(Endpoint(path: "mobile/v2/lists/update", method: .post,
                                    body: ListBody(listId: id, name: name, listDesc: description,
                                                   isPrivate: isPrivate, films: nil)),
                           as: IgnoredResponse.self)
    }

    /// `mode` is "add", "remove" or "set".
    func updateListItems(id: Int, mode: String, films: [Int]) async throws {
        _ = try await send(Endpoint(path: "mobile/v2/lists/update-items", method: .post,
                                    body: ListItemsBody(listId: id, mode: mode, films: films)),
                           as: IgnoredResponse.self)
    }

    func deleteList(id: Int) async throws {
        _ = try await send(Endpoint(path: "mobile/v2/lists/delete", method: .delete,
                                    query: ["list_id": String(id)]),
                           as: IgnoredResponse.self)
    }
}

private struct ListBody: Encodable {
    let listId: Int?
    let name: String
    let listDesc: String
    let isPrivate: Bool
    let films: [Int]?
}

private struct ListItemsBody: Encodable {
    let listId: Int
    let mode: String
    let films: [Int]
}
