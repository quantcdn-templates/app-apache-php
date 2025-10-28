<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Apache + PHP Template</title>
    <style>
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; 
            margin: 0; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container { 
            max-width: 800px; 
            background: white; 
            border-radius: 10px; 
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        .header { 
            background: #333; 
            color: white; 
            padding: 30px; 
            text-align: center;
        }
        .content { 
            padding: 30px; 
        }
        .info-box { 
            background: #f8f9fa; 
            padding: 20px; 
            border-radius: 8px; 
            margin: 20px 0; 
            border-left: 4px solid #007bff;
        }
        .status-item {
            display: flex;
            justify-content: space-between;
            padding: 10px 0;
            border-bottom: 1px solid #eee;
        }
        .status-value {
            font-weight: bold;
            color: #28a745;
        }
        .btn {
            display: inline-block;
            padding: 12px 24px;
            background: #007bff;
            color: white;
            text-decoration: none;
            border-radius: 5px;
            margin: 10px 5px;
            transition: background 0.3s;
        }
        .btn:hover {
            background: #0056b3;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Apache + PHP Template</h1>
            <p>Quant Cloud ready Apache HTTP Server with PHP</p>
        </div>
        
        <div class="content">
            <div class="info-box">
                <h2>✅ Application Status</h2>
                <div class="status-item">
                    <span>PHP Version:</span>
                    <span class="status-value"><?php echo PHP_VERSION; ?></span>
                </div>
                <div class="status-item">
                    <span>Server Software:</span>
                    <span class="status-value"><?php echo $_SERVER['SERVER_SOFTWARE'] ?? 'Unknown'; ?></span>
                </div>
                <div class="status-item">
                    <span>Document Root:</span>
                    <span class="status-value"><?php echo $_SERVER['DOCUMENT_ROOT'] ?? 'Unknown'; ?></span>
                </div>
                <div class="status-item">
                    <span>Server Name:</span>
                    <span class="status-value"><?php echo $_SERVER['SERVER_NAME'] ?? 'Unknown'; ?></span>
                </div>
                <div class="status-item">
                    <span>Host Header:</span>
                    <span class="status-value"><?php echo $_SERVER['HTTP_HOST'] ?? 'Unknown'; ?></span>
                </div>
                <?php if (function_exists('opcache_get_status')): ?>
                <div class="status-item">
                    <span>OPcache:</span>
                    <span class="status-value"><?php echo opcache_get_status() ? 'Enabled' : 'Disabled'; ?></span>
                </div>
                <?php endif; ?>
            </div>

            <div class="info-box">
                <h2>🔧 Common Extensions</h2>
                    APCu, BCMath, GD, Imagick, OPcache, PDO MySQL, PDO PostgreSQL, Redis, Sockets, ZIP<br/><br/>
                    <a href="?view=extensions">See all extensions</a>
                </p>
            </div>

            <div style="text-align: center; margin-top: 30px;">
                <a href="?view=db" class="btn">🗄️ Test Database</a>
                <a href="?view=extensions" class="btn">🔧 View Extensions</a>
            </div>

            <?php if (isset($_GET['view']) && $_GET['view'] === 'extensions'): ?>
                <div class="info-box" style="margin-top: 30px;">
                    <h2>Loaded PHP Extensions</h2>
                    <div style="columns: 3; column-gap: 20px;">
                        <?php 
                        $extensions = get_loaded_extensions();
                        sort($extensions);
                        foreach ($extensions as $ext): ?>
                            <div style="break-inside: avoid; margin-bottom: 5px;">
                                <strong><?php echo htmlspecialchars($ext); ?></strong>
                            </div>
                        <?php endforeach; ?>
                    </div>
                </div>
            <?php endif; ?>

            <?php if (isset($_GET['view']) && $_GET['view'] === 'db'): ?>
                <div class="info-box" style="margin-top: 30px;">
                    <h2>Database Connection Test</h2>
                    <?php
                    try {
                        $host = $_ENV['DB_HOST'] ?? 'db';
                        $dbname = $_ENV['DB_DATABASE'] ?? 'apache_php';
                        $username = $_ENV['DB_USERNAME'] ?? 'apache_php';
                        $password = $_ENV['DB_PASSWORD'] ?? 'apache_php';
                        
                        // Enable TLS/SSL for RDS database connections when certificate is available
                        // Can be disabled for local development with DISABLE_DB_TLS=true
                        $options = [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION];
                        $caPath = '/opt/rds-ca-certs/rds-ca-cert-bundle.pem';
                        $sslEnabled = false;
                        
                        if (($_ENV['DISABLE_DB_TLS'] ?? 'false') !== 'true' && file_exists($caPath)) {
                            $options[PDO::MYSQL_ATTR_SSL_CA] = $caPath;
                            $options[PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT] = true;
                            $sslEnabled = true;
                        }
                        
                        $pdo = new PDO("mysql:host=$host;dbname=$dbname", $username, $password, $options);
                        echo "<p style='color: green;'>✅ Database connection successful!</p>";
                        echo "<p><strong>Host:</strong> " . htmlspecialchars($host) . "<br>";
                        echo "<strong>Database:</strong> " . htmlspecialchars($dbname) . "<br>";
                        echo "<strong>Username:</strong> " . htmlspecialchars($username) . "<br>";
                        echo "<strong>SSL/TLS:</strong> " . ($sslEnabled ? 'Enabled ✓' : 'Disabled') . "</p>";
                    } catch (PDOException $e) {
                        echo "<p style='color: red;'>❌ Database connection failed: " . htmlspecialchars($e->getMessage()) . "</p>";
                    }
                    ?>
                </div>
            <?php endif; ?>
        </div>
    </div>
</body>
</html>
