const express = require('express');
const app = express();

const deploymentTime = new Date().toISOString();
const version = process.env.APP_VERSION || '1.0.0';

// In-memory storage for timesheets
const timesheets = [];
let requestCount = 0;

app.use(express.json());
app.use(express.static('public'));

// Logging middleware
app.use((req, res, next) => {
    requestCount++;
    const timestamp = new Date().toISOString();
    console.log(`[${timestamp}] ${req.method} ${req.path} - Request #${requestCount}`);
    next();
});

app.get('/', (req, res) => {
    console.log('[INFO] Home page accessed');
    res.send(`
<!DOCTYPE html>
<html>
<head>
    <title>Timesheet App - CI/CD Demo</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); min-height: 100vh; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 12px; box-shadow: 0 10px 40px rgba(0,0,0,0.2); }
        h1 { color: #667eea; margin-top: 0; }
        .status { color: #28a745; font-weight: bold; font-size: 18px; }
        .info { background: #f8f9fa; padding: 15px; border-radius: 8px; margin: 20px 0; border-left: 4px solid #667eea; }
        .form-group { margin: 15px 0; }
        label { display: block; margin-bottom: 5px; font-weight: bold; color: #333; }
        input, select { width: 100%; padding: 10px; border: 2px solid #e0e0e0; border-radius: 6px; font-size: 14px; }
        button { background: #667eea; color: white; padding: 12px 30px; border: none; border-radius: 6px; cursor: pointer; font-size: 16px; font-weight: bold; }
        button:hover { background: #5568d3; }
        .timesheet-list { margin-top: 30px; }
        .timesheet-item { background: #f8f9fa; padding: 15px; margin: 10px 0; border-radius: 8px; border-left: 4px solid #28a745; }
        .stats { display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; margin: 20px 0; }
        .stat-card { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 8px; text-align: center; }
        .stat-value { font-size: 32px; font-weight: bold; }
        .stat-label { font-size: 14px; opacity: 0.9; }
    </style>
</head>
<body>
    <div class="container">
        <h1>⏰ Timesheet Tracker</h1>
        <p class="status">✓ System Online</p>
        
        <div class="stats">
            <div class="stat-card">
                <div class="stat-value" id="totalEntries">0</div>
                <div class="stat-label">Total Entries</div>
            </div>
            <div class="stat-card">
                <div class="stat-value" id="totalHours">0</div>
                <div class="stat-label">Total Hours</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">${requestCount}</div>
                <div class="stat-label">API Requests</div>
            </div>
        </div>

        <div class="info">
            <p><strong>Version:</strong> ${version}</p>
            <p><strong>Deployed:</strong> ${deploymentTime}</p>
            <p><strong>Server Time:</strong> ${new Date().toLocaleString()}</p>
        </div>

        <h2>Submit Timesheet</h2>
        <form id="timesheetForm">
            <div class="form-group">
                <label>Employee Name</label>
                <input type="text" id="name" required>
            </div>
            <div class="form-group">
                <label>Date</label>
                <input type="date" id="date" required>
            </div>
            <div class="form-group">
                <label>Hours Worked</label>
                <input type="number" id="hours" min="0" max="24" step="0.5" required>
            </div>
            <div class="form-group">
                <label>Project</label>
                <select id="project" required>
                    <option value="">Select Project</option>
                    <option value="CI/CD Pipeline">CI/CD Pipeline</option>
                    <option value="Web Development">Web Development</option>
                    <option value="DevOps">DevOps</option>
                    <option value="Testing">Testing</option>
                </select>
            </div>
            <button type="submit">Submit Timesheet</button>
        </form>

        <div class="timesheet-list">
            <h2>Recent Timesheets</h2>
            <div id="timesheets"></div>
        </div>
    </div>

    <script>
        function loadTimesheets() {
            fetch('/api/timesheets')
                .then(r => r.json())
                .then(data => {
                    document.getElementById('totalEntries').textContent = data.total;
                    document.getElementById('totalHours').textContent = data.totalHours;
                    
                    const html = data.timesheets.map(t => 
                        '<div class="timesheet-item">' +
                            '<strong>' + t.name + '</strong> - ' + t.project + '<br>' +
                            'Date: ' + t.date + ' | Hours: ' + t.hours + '<br>' +
                            '<small>Submitted: ' + new Date(t.timestamp).toLocaleString() + '</small>' +
                        '</div>'
                    ).join('');
                    document.getElementById('timesheets').innerHTML = html || '<p>No timesheets yet</p>';
                });
        }

        document.getElementById('timesheetForm').onsubmit = async (e) => {
            e.preventDefault();
            const data = {
                name: document.getElementById('name').value,
                date: document.getElementById('date').value,
                hours: parseFloat(document.getElementById('hours').value),
                project: document.getElementById('project').value
            };
            
            await fetch('/api/timesheets', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify(data)
            });
            
            e.target.reset();
            loadTimesheets();
        };

        loadTimesheets();
        setInterval(loadTimesheets, 5000);
    </script>
</body>
</html>
    `);
});

app.get('/api/timesheets', (req, res) => {
    console.log(`[INFO] Fetching timesheets - Total: ${timesheets.length}`);
    const totalHours = timesheets.reduce((sum, t) => sum + t.hours, 0);
    res.json({
        total: timesheets.length,
        totalHours: totalHours.toFixed(1),
        timesheets: timesheets.slice(-10).reverse()
    });
});

app.post('/api/timesheets', (req, res) => {
    const entry = {
        ...req.body,
        timestamp: new Date().toISOString(),
        id: Date.now()
    };
    timesheets.push(entry);
    console.log(`[SUCCESS] Timesheet submitted: ${entry.name} - ${entry.hours}h on ${entry.project}`);
    res.json({ success: true, entry });
});

app.get('/api/info', (req, res) => {
    console.log('[INFO] System info requested');
    res.json({
        version,
        deploymentTime,
        status: "running",
        totalTimesheets: timesheets.length,
        totalRequests: requestCount
    });
});

app.get('/health', (req, res) => {
    console.log('[HEALTH] Health check performed');
    res.status(200).json({
        status: "healthy",
        uptime: process.uptime(),
        timestamp: new Date().toISOString()
    });
});

// Only start server if this file is run directly (not imported for tests)
if (require.main === module) {
    const port = process.env.PORT || 5000;
    app.listen(port, '0.0.0.0', () => {
        console.log(`Server running on port ${port}`);
    });
}

module.exports = app;