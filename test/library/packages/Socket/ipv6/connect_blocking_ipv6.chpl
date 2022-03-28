use UnitTest;
use Socket;

proc test_connection_ipv6_dns(test: borrowed Test) throws {
  var port:uint(16) = 8814;
  var host = "localhost";
  var address = ipAddr.ipv6(IPv6Localhost, port);
  var server = listen(address);
  sync {
    begin {
      var conn = server.accept();
    }
    var conn = connect(host, port, IPFamily.IPv6);
    test.assertEqual(conn.addr, address);
  }
}

proc test_connection_ipv6_ipaddr(test: borrowed Test) throws {
  var port:uint(16) = 8815;
  var address = ipAddr.ipv6(IPv6Localhost, port);
  var server = listen(address);
  sync {
    begin {
      var conn = server.accept();
    }
    var conn = connect(address);
    test.assertEqual(conn.addr, address);
  }
}

proc test_fail_ipv6_noserver(test: borrowed Test) throws {
  var port:uint(16) = 8816;
  var host = "::1";
  var address = ipAddr.ipv6(IPv6Localhost, port);

  try {
    var conn = connect(address);
    // making error fail programatically.
    test.assertEqual(-1, 0);
    conn.close();
  }
  catch e {
    test.assertEqual(e.message(), "Connection refused (connect() failed)");
  }
}

UnitTest.main();
