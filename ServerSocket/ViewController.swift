//
//  ViewController.swift
//  ServerSocket
//
//  Created by Dmitry Bespalov on 01/03/17.
//  Copyright © 2017 Dmitry Bespalov. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    var server = Server()
    var client = Client()

    override func viewDidLoad() {
        super.viewDidLoad()
        // On my computer I got the following error from libnetwork.dylib:
        //      nw_socket_set_common_sockopts setsockopt SO_NOAPNFALLBK failed: [42] Protocol not available, dumping backtrace
        // I've added OS_ACTIVITY_MODE=$(DEBUG_ACTIVITY_MODE) Environment variable to the scheme
        //  and set DEBUG_ACTIVITY_MODE custom build setting to "disable" for Debug configuration
        server.start(port: 8080)
        client.start(port: 8080)
    }

    deinit {
        server.stop()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

