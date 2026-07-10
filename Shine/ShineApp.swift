//
//  ShineApp.swift
//  Shine
//
//  Created by Adem Ayar on 10.07.2026.
//

import SwiftUI
import CoreData

@main
struct ShineApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
