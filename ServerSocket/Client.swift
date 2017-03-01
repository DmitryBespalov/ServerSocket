//
//  Client.swift
//  ServerSocket
//
//  Created by Dmitry Bespalov on 01/03/17.
//  Copyright © 2017 Dmitry Bespalov. All rights reserved.
//

import Foundation



class Client {

    func start(port: Int) {
        guard let url = URL(string: "https://localhost:\(port)/") else { fatalError("Invalid server url") }
        let session = URLSession(configuration: URLSessionConfiguration.default, delegate: nil, delegateQueue: nil)

        session.dataTask(with: url) { data, response, error in
            print("Data: \(data) Response: \(response) Error: \(error)")
            if let data = data {
                print("Received: \(String(data: data, encoding: String.Encoding.utf8) ?? "")")
            }
        }.resume()
    }

}
