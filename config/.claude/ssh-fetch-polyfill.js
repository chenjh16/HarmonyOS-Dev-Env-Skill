// SSH Environment Fetch Polyfill
// When running in SSH sessions on HarmonyOS, we use --jitless to avoid V8 crash
// But --jitless disables WebAssembly, breaking native fetch
// This script polyfills fetch with node-fetch (based on http.request)
//
// IMPORTANT: In --jitless mode, native fetch exists but is broken (WebAssembly is undefined)
// So we must check WebAssembly, not just fetch existence
//
// COMPATIBILITY FIXES:
// 1. node-fetch@2 Response.body is Node.js Readable stream, lacks cancel() method
// 2. node-fetch@2 Response.body is NOT Web ReadableStream (no pipeThrough/getReader)
// 3. MCP SDK uses Web Streams API: body.pipeThrough(new TextDecoderStream)...
// 4. Readable.toWeb() consumes the original stream, breaking text()/json()
// 5. SSH remote execution doesn't pass shell env vars to Node.js - must load .env directly
// 6. Solution: Override Response prototype methods to handle stream conversion lazily

if (typeof WebAssembly === 'undefined') {
    console.log('[SSH] WebAssembly disabled (--jitless mode), polyfilling fetch with node-fetch...');

    // Load environment variables from .env file (SSH remote execution doesn't pass shell env)
    const fs = require('fs');
    const envPath = process.env.HOME + '/.claude/.env';
    if (fs.existsSync(envPath) && !process.env.ANTHROPIC_API_KEY) {
        const envContent = fs.readFileSync(envPath, 'utf8');
        const lines = envContent.split('\n');
        for (const line of lines) {
            const trimmed = line.trim();
            if (trimmed && !trimmed.startsWith('#') && trimmed.includes('=')) {
                const [key, ...valueParts] = trimmed.split('=');
                const value = valueParts.join('=');
                if (key && value && key.startsWith('ANTHROPIC_')) {
                    process.env[key] = value;
                }
            }
        }
        console.log('[SSH] Environment loaded from .env');
    }

    try {
        const nodeFetch = require('/storage/Users/currentUser/Claude/node_modules/node-fetch');
        const { Readable } = require('stream');

        // Store original Response class
        const OriginalResponse = nodeFetch.Response;

        // Create a custom Response class that handles stream conversion properly
        class CustomResponse extends OriginalResponse {
            constructor(body, init) {
                super(body, init);
                this._nodeStream = body; // Store original Node stream
                this._webStream = null;  // Lazy-initialized web stream
            }

            // Override body getter to return Web ReadableStream when needed
            get body() {
                // If already converted, return cached web stream
                if (this._webStream) {
                    return this._webStream;
                }

                // If this is a Node stream, convert to Web ReadableStream
                // But DON'T consume it - use a tee/clone approach
                if (this._nodeStream && typeof Readable.toWeb === 'function') {
                    // Clone the stream before conversion to avoid consuming it
                    // Node.js streams can't be cloned, so we buffer the content
                    // Alternative: Create a pass-through that copies data

                    // For MCP SDK compatibility, return web stream
                    // But text()/json() will read from buffer, not from stream
                    this._webStream = Readable.toWeb(this._nodeStream);
                    this._webStream.cancel = async function(reason) {
                        const reader = this._webStream.getReader();
                        await reader.cancel(reason);
                    };
                    return this._webStream;
                }

                // Fallback: return null or original body
                return null;
            }

            // Override text() to use node-fetch's original implementation
            async text() {
                // Use node-fetch's buffer method which handles Node streams correctly
                const buffer = await this.buffer();
                return buffer.toString('utf-8');
            }

            // Override json() to use our text() method
            async json() {
                const text = await this.text();
                return JSON.parse(text);
            }

            // Override buffer() to properly handle Node streams
            async buffer() {
                if (this._nodeStream) {
                    // Read from Node stream directly
                    return new Promise((resolve, reject) => {
                        const chunks = [];
                        this._nodeStream.on('data', chunk => chunks.push(chunk));
                        this._nodeStream.on('end', () => resolve(Buffer.concat(chunks)));
                        this._nodeStream.on('error', reject);
                    });
                }
                return super.buffer();
            }
        }

        // Simple polyfill - just wrap node-fetch and return CustomResponse
        globalThis.fetch = async function(url, opts) {
            const response = await nodeFetch(url, opts);
            // Return a CustomResponse that wraps the original
            return new CustomResponse(response.body, {
                status: response.status,
                statusText: response.statusText,
                headers: response.headers
            });
        };

        globalThis.Headers = nodeFetch.Headers;
        globalThis.Request = nodeFetch.Request;
        globalThis.Response = CustomResponse;

        console.log('[SSH] fetch polyfill loaded successfully (CustomResponse with lazy stream conversion)');
    } catch (e) {
        console.error('[SSH] Failed to load node-fetch:', e.message);
        console.error('[SSH] Stack:', e.stack);
    }
}