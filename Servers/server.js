const WebSocket = require('ws');
const chalk = require('chalk');  // 需要先安装：npm install chalk@4

//默认世界地图大小（正方形）
const WORLD_SIZE = {
    minX: 0,
    maxX: 5000,
    minY: 0,
    maxY: 5000
};

// 服务器配置
const CONFIG = {
    port: 8080,
    maxPlayers: 100,
    version: '1.0.1'
};

// 控制台颜色
const COLORS = {
    info: chalk.blue,//普通信息
    success: chalk.green,//成功信息
    warning: chalk.yellow,//警告信息
    error: chalk.red,//错误信息
    player: chalk.cyan,//青色 //玩家相关信息
    system: chalk.magenta//洋红色 //系统相关信息
};

// 服务器状态
const SERVER_STATUS = {
    players: new Map(),     // 存储所有连接的客户端
    colors: new Map(),      // 存储玩家颜色
    names: new Map(),       // 存储玩家名称
    startTime: Date.now(),  // 服务器启动时间
    items: new Map()        // 存储道具信息
};

// 添加房间系统
const ROOM_STATUS = {
    players: new Map(),         // 存储房间中的玩家
    playerReadyStatus: new Map(), // 存储玩家准备状态
    playerNames: new Map()      // 存储房间中玩家名称
};

// 预定义的玩家显示颜色列表
const PLAYER_COLORS = [
    { r: 1, g: 0.5, b: 0.5 }, // 红色
    { r: 0.5, g: 1, b: 0.5 }, // 绿色
    { r: 0.5, g: 0.5, b: 1 }, // 蓝色
    { r: 1, g: 1, b: 0.5 },   // 黄色
    { r: 1, g: 0.5, b: 1 },   // 粉色
    { r: 0.5, g: 1, b: 1 }    // 青色
];

// 简单封装了一个服务器控制台日志函数
/* function log(type, message) {
    const timestamp = new Date().toLocaleTimeString();
    console.log(`${COLORS.system(`[${timestamp}]`)} ${COLORS[type](message)}`);
} */

// 简单封装了一个服务器控制台日志函数
function log(type, message) {
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    const time = now.toLocaleTimeString();
    const timestamp = `${year}-${month}-${day} ${time}`;

    console.log(`${COLORS.system(`[${timestamp}]`)} ${COLORS[type](message)}`);
}

// 获取运行时间
function getUptime() {
    const uptime = Date.now() - SERVER_STATUS.startTime;
    const hours = Math.floor(uptime / 3600000);
    const minutes = Math.floor((uptime % 3600000) / 60000);
    const seconds = Math.floor((uptime % 60000) / 1000);
    return `${hours}h ${minutes}m ${seconds}s`;
}

// 分配新的颜色
function assignColor() {
    const usedColors = Array.from(SERVER_STATUS.colors.values());
    const availableColors = PLAYER_COLORS.filter(color => 
        !usedColors.some(used => 
            used.r === color.r && used.g === color.g && used.b === color.b
        )
    );
    
    if (availableColors.length > 0) {
        return availableColors[Math.floor(Math.random() * availableColors.length)];
    }
    return { r: Math.random(), g: Math.random(), b: Math.random() };
}

// 生成随机出生点
function getRandomSpawnPoint() {
    const spawnArea = {
        minX: WORLD_SIZE.minX,
        maxX: WORLD_SIZE.maxX,
        minY: WORLD_SIZE.minY,
        maxY: WORLD_SIZE.maxY
    };
    
    return {
        x: Math.random() * (spawnArea.maxX - spawnArea.minX) + spawnArea.minX,
        y: Math.random() * (spawnArea.maxY - spawnArea.minY) + spawnArea.minY
    };
}

// 生成随机道具位置
function getRandomItemPosition() {
    const position = {
        x: Math.random() * WORLD_SIZE.maxX,
        y: Math.random() * WORLD_SIZE.maxY
    };
    
    log('info', `生成道具位置: X: ${Math.round(position.x)}, Y: ${Math.round(position.y)}`);
    return position;
}

// 生成道具
function spawnItem() {
    const itemId = Date.now().toString();
    const position = getRandomItemPosition();
    const itemType = Math.random() < 0.5 ? 'health' : 'ammo';  // 随机选择道具类型
    
    // 广播道具生成消息
    SERVER_STATUS.players.forEach((client) => {
        if (client.readyState === WebSocket.OPEN) {
            client.send(JSON.stringify({
                type: 'spawn_item',
                item_id: itemId,
                item_type: itemType,
                position: position
            }));
        }
    });
    
    // 记录道具信息
    SERVER_STATUS.items.set(itemId, {
        position: position,
        type: itemType,
        spawnTime: Date.now()
    });
    
    log('info', `生成${itemType === 'health' ? '生命值' : '弹药'}道具 (ID: ${itemId})`);
}

// 创建服务器
const server = new WebSocket.Server({ port: CONFIG.port });

// 服务器启动信息
log('info', `正在启动多人游戏服务器 v${CONFIG.version}...`);
log('info', `端口: ${CONFIG.port}`);
log('info', `最大玩家数: ${CONFIG.maxPlayers}`);
log('success', '服务器启动完成！输入 "help" 查看可用命令');

// 处理控制台输入
const readline = require('readline');
const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
});

// 强制关闭所有连接并停止服务器
function stopServer() {
    log('warning', '正在关闭服务器...');
    
    // 向所有客户端发送服务器关闭消息并强制关闭连接
    for (const [clientId, client] of SERVER_STATUS.players) {
        try {
            if (client.readyState === WebSocket.OPEN) {
                client.send(JSON.stringify({
                    type: 'server_shutdown'
                }));
                client.terminate();
            }
        } catch (error) {
            log('error', `关闭客户端连接时出错: ${error.message}`);
        }
    }
    
    // 向所有房间玩家发送服务器关闭消息
    for (const [clientId, client] of ROOM_STATUS.players) {
        try {
            if (client.readyState === WebSocket.OPEN) {
                client.send(JSON.stringify({
                    type: 'server_shutdown'
                }));
                client.terminate();
            }
        } catch (error) {
            log('error', `关闭房间客户端连接时出错: ${error.message}`);
        }
    }
    
    // 清理所有状态
    SERVER_STATUS.players.clear();
    SERVER_STATUS.colors.clear();
    SERVER_STATUS.names.clear();
    SERVER_STATUS.items.clear();
    ROOM_STATUS.players.clear();
    ROOM_STATUS.playerReadyStatus.clear();
    ROOM_STATUS.playerNames.clear();
    
    // 关闭 readline 接口
    rl.close();
    
    // 关闭 WebSocket 服务器
    server.close(() => {
        log('success', '服务器已关闭');
        // 强制退出进程
        setTimeout(() => {
            process.exit(0);
        }, 1000);
    });
}

// 修改命令处理部分
rl.on('line', (input) => {
    const command = input.trim().toLowerCase();
    
    switch (command) {
        case 'help':
            log('info', '可用命令:');
            log('info', 'help - 显示帮助信息');
            log('info', 'list - 显示在线玩家');
            log('info', 'status - 显示服务器状态');
            log('info', 'stop - 停止服务器');
            break;
            
        case 'list':
            log('info', `房间中的玩家 (${ROOM_STATUS.players.size}):`);
            ROOM_STATUS.players.forEach((_, id) => {
                const name = ROOM_STATUS.playerNames.get(id) || 'Unknown';
                const ready = ROOM_STATUS.playerReadyStatus.get(id) ? '(已准备)' : '(未准备)';
                log('player', `- ${name} ${ready} (ID: ${id})`);
            });
            
            log('info', `游戏中的玩家 (${SERVER_STATUS.players.size}/${CONFIG.maxPlayers}):`);
            SERVER_STATUS.players.forEach((_, id) => {
                const name = SERVER_STATUS.names.get(id) || 'Unknown';
                log('player', `- ${name} (ID: ${id})`);
            });
            break;
            
        case 'status':
            log('info', '服务器状态:');
            log('info', `运行时间: ${getUptime()}`);
            log('info', `房间中的玩家: ${ROOM_STATUS.players.size}`);
            log('info', `游戏中的玩家: ${SERVER_STATUS.players.size}/${CONFIG.maxPlayers}`);
            log('info', `内存使用: ${Math.round(process.memoryUsage().heapUsed / 1024 / 1024)}MB`);
            break;
            
        case 'stop':
            if (SERVER_STATUS.players.size > 0 || ROOM_STATUS.players.size > 0) {
                log('warning', `当前有 ${SERVER_STATUS.players.size + ROOM_STATUS.players.size} 个玩家在线`);
                log('warning', '正在强制关闭所有连接...');
            }
            stopServer();
            break;
            
        default:
            log('error', '未知命令。输入 "help" 查看可用命令');
    }
});

// 处理新连接
server.on('connection', (ws) => {
    const clientId = Date.now().toString();
    // 不要立即将客户端添加到游戏玩家列表，而是先添加到客户端列表
    const clients = {}; // 确保在全局定义了这个变量
    clients[clientId] = ws;
    
    log('success', `新客户端连接 (ID: ${clientId})`);
    
    // 只发送初始化ID，不包含颜色和位置
    ws.send(JSON.stringify({
        type: 'init',
        id: clientId
    }));
    
    // 处理消息
    ws.on('message', (message) => {
        try {
            const data = JSON.parse(message);
            handleMessage(clientId, data, ws);
        } catch (error) {
            log('error', `解析消息错误: ${error.message}`);
        }
    });
    
    // 处理断开连接
    ws.on('close', () => {
        // 检查玩家是否在房间中
        if (ROOM_STATUS.players.has(clientId)) {
            const playerName = ROOM_STATUS.playerNames.get(clientId) || 'Unknown';
            log('warning', `玩家 ${playerName} (ID: ${clientId}) 离开了房间`);
            
            // 通知其他房间玩家
            ROOM_STATUS.players.forEach((client, id) => {
                if (id !== clientId && client.readyState === WebSocket.OPEN) {
                    client.send(JSON.stringify({
                        type: 'room_player_left',
                        id: clientId
                    }));
                }
            });
            
            // 清理房间数据
            ROOM_STATUS.players.delete(clientId);
            ROOM_STATUS.playerReadyStatus.delete(clientId);
            ROOM_STATUS.playerNames.delete(clientId);
            
            // 检查是否所有玩家都准备好了
            checkAllPlayersReady();
        }
        // 检查玩家是否在游戏中
        else if (SERVER_STATUS.players.has(clientId)) {
            const playerName = SERVER_STATUS.names.get(clientId) || 'Unknown';
            log('warning', `玩家 ${playerName} (ID: ${clientId}) 离开了游戏`);
            
            // 通知其他游戏玩家
            SERVER_STATUS.players.forEach((client, id) => {
                if (id !== clientId && client.readyState === WebSocket.OPEN) {
                    client.send(JSON.stringify({
                        type: 'player_left',
                        id: clientId
                    }));
                }
            });
            
            // 清理游戏数据
            SERVER_STATUS.players.delete(clientId);
            SERVER_STATUS.colors.delete(clientId);
            SERVER_STATUS.names.delete(clientId);
        }
        
        // 从客户端列表中移除
        delete clients[clientId];
        
        log('info', `当前在线玩家: ${SERVER_STATUS.players.size}/${CONFIG.maxPlayers}`);
    });
});

// 修改消息处理函数，添加ws参数
function handleMessage(clientId, data, ws) {
    //console.log(`收到来自 ${clientId} 的消息:`, data.type);
    
    switch (data.type) {
        case 'player_name':
            // 这是从房间发来的消息
            ROOM_STATUS.players.set(clientId, ws);
            ROOM_STATUS.playerNames.set(clientId, data.name);
            ROOM_STATUS.playerReadyStatus.set(clientId, false);
            
            log('player', `玩家 ${data.name} (ID: ${clientId}) 加入了房间`);
            
            // 通知所有房间中的玩家有新玩家加入
            ROOM_STATUS.players.forEach((client, id) => {
                if (client.readyState === WebSocket.OPEN) {
                    client.send(JSON.stringify({
                        type: 'room_player_joined',
                        id: clientId,
                        name: data.name,
                        ready: false
                    }));
                }
            });
            
            // 向新玩家发送当前房间中的所有玩家信息
            ROOM_STATUS.players.forEach((client, id) => {
                if (id !== clientId && client.readyState === WebSocket.OPEN) {
                    ws.send(JSON.stringify({
                        type: 'room_player_joined',
                        id: id,
                        name: ROOM_STATUS.playerNames.get(id),
                        ready: ROOM_STATUS.playerReadyStatus.get(id)
                    }));
                }
            });
            break;
            
        case 'player_ready':
            // 玩家准备状态更新
            if (ROOM_STATUS.players.has(clientId)) {
                ROOM_STATUS.playerReadyStatus.set(clientId, data.ready);
                
                // 通知所有房间中的玩家
                ROOM_STATUS.players.forEach((client, id) => {
                    if (client.readyState === WebSocket.OPEN) {
                        client.send(JSON.stringify({
                            type: 'player_ready_status',
                            id: clientId,
                            ready: data.ready
                        }));
                    }
                });
                
                // 检查是否所有玩家都准备好了
                checkAllPlayersReady();
            }
            break;
            
        case 'enter_game':
            // 玩家从房间进入游戏
            const playerName = data.name;
            const color = assignColor();
            const spawnPoint = getRandomSpawnPoint();
            
            // 添加到游戏玩家列表
            SERVER_STATUS.players.set(clientId, ws);
            SERVER_STATUS.colors.set(clientId, color);
            SERVER_STATUS.names.set(clientId, playerName);
            
            // 发送游戏初始化消息
            ws.send(JSON.stringify({
                type: 'game_init',
                id: clientId,
                color: color,
                position: spawnPoint
            }));
            
            log('player', `玩家 ${playerName} (ID: ${clientId}) 进入游戏`);
            log('info', `出生点: X: ${Math.round(spawnPoint.x)}, Y: ${Math.round(spawnPoint.y)}`);
            
            // 通知该玩家关于所有其他玩家
            SERVER_STATUS.players.forEach((client, id) => {
                if (id !== clientId && client.readyState === WebSocket.OPEN) {
                    ws.send(JSON.stringify({
                        type: 'player_joined',
                        id: id,
                        color: SERVER_STATUS.colors.get(id),
                        name: SERVER_STATUS.names.get(id),
                        position: spawnPoint
                    }));
                }
            });
            
            // 通知所有其他玩家关于这个新玩家
            SERVER_STATUS.players.forEach((client, id) => {
                if (id !== clientId && client.readyState === WebSocket.OPEN) {
                    client.send(JSON.stringify({
                        type: 'player_joined',
                        id: clientId,
                        color: color,
                        name: playerName,
                        position: spawnPoint
                    }));
                }
            });
            
            // 如果这是第一个玩家，开始生成道具
            if (SERVER_STATUS.players.size === 1) {
                startItemSpawnLoop();
            }
            break;
            
        // 其他消息类型处理...
        case 'position_update':
        case 'shoot':
        case 'health_update':
            // 转发给其他玩家
            SERVER_STATUS.players.forEach((client, id) => {
                if (id !== clientId && client.readyState === WebSocket.OPEN) {
                    client.send(JSON.stringify({
                        ...data,
                        id: clientId
                    }));
                }
            });
            break;
            
        case 'game_over':
            log('info', `游戏结束！获胜者: ${data.winner}`);
            // 广播游戏结束消息
            SERVER_STATUS.players.forEach((client) => {
                if (client.readyState === WebSocket.OPEN) {
                    client.send(JSON.stringify(data));
                }
            });
            break;
    }
}

// 修改道具生成循环，不要在服务器启动时就开始
// startItemSpawnLoop();

// 修改道具生成循环函数
function startItemSpawnLoop() {
    log('info', '开始生成道具');
    
    // 清除可能存在的旧定时器
    if (global.itemSpawnTimer) {
        clearInterval(global.itemSpawnTimer);
    }
    
    // 创建新的定时器
    global.itemSpawnTimer = setInterval(() => {
        if (SERVER_STATUS.players.size > 0) {
            spawnItem();
        } else {
            // 如果没有玩家，停止生成道具
            clearInterval(global.itemSpawnTimer);
            global.itemSpawnTimer = null;
            log('info', '停止生成道具');
        }
    }, 5000); // 每5秒生成一个道具
}

// 检查是否所有玩家都准备好了
function checkAllPlayersReady() {
    const playerCount = ROOM_STATUS.players.size;
    
    // 如果房间中没有玩家或只有一个玩家，不开始游戏
    if (playerCount <= 1) {
        return;
    }
    
    // 检查是否所有玩家都准备好了
    let allReady = true;
    for (const [playerId, ready] of ROOM_STATUS.playerReadyStatus.entries()) {
        if (!ready) {
            allReady = false;
            break;
        }
    }
    
    // 如果所有玩家都准备好了，开始游戏
    if (allReady) {
        log('info', '所有玩家都准备好了，开始游戏');
        
        // 通知所有玩家游戏开始
        ROOM_STATUS.players.forEach((client) => {
            if (client.readyState === WebSocket.OPEN) {
                client.send(JSON.stringify({
                    type: 'start_game'
                }));
            }
        });
    }
}

// 处理服务器错误
server.on('error', (error) => {
    log('error', `服务器错误: ${error.message}`);
});

// 处理进程退出信号
process.on('SIGINT', () => {
    stopServer();
});

// 处理未捕获的异常
process.on('uncaughtException', (error) => {
    log('error', `未捕获的异常: ${error.message}`);
    stopServer();
});

// 处理未处理的 Promise 拒绝
process.on('unhandledRejection', (reason, promise) => {
    log('error', `未处理的 Promise 拒绝: ${reason}`);
    stopServer();
}); 