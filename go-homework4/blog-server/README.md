# 个人博客系统后端 - Gin+GORM+PostgreSQL
## 作业实现说明
基于Go语言开发，使用Gin框架+GORM+PostgreSQL实现，包含用户JWT认证、文章CRUD、评论功能，完全满足作业要求。

## 一、技术栈
1. 框架：Gin Web Framework
2. ORM：GORM v2
3. 数据库：PostgreSQL 14+
4. 认证：JWT(JSON Web Token)
5. 密码加密：bcrypt
6. 日志：logrus

## 二、环境要求
1. Go 1.20+
2. PostgreSQL 14+
3. 已创建数据库：blog

## 三、项目启动步骤
1. 克隆项目到本地，进入项目根目录
2. 初始化依赖：go mod tidy
3. 修改main.go中PostgreSQL的连接密码，替换为自己的数据库密码
4. 启动项目：go run main.go
5. 服务启动后，访问地址：http://localhost:8080

## 四、数据库表结构
自动迁移生成3张表：
- users：用户信息表
- posts：文章信息表（关联用户）
- comments：评论信息表（关联用户+文章）

## 五、接口说明
### 公开接口（无需登录）
- POST /api/register ：用户注册
- POST /api/login    ：用户登录
- GET  /api/posts    ：获取所有文章
- GET  /api/posts/:id：获取单篇文章详情
- GET  /api/posts/:id/comments：获取文章评论列表

### 私有接口（需要JWT认证，请求头带Authorization: Bearer token）
- POST   /api/posts    ：创建文章
- PUT    /api/posts/:id：更新文章（仅作者）
- DELETE /api/posts/:id：删除文章（仅作者）
- POST   /api/comments ：发表评论

## 六、功能说明
1. 用户注册时密码进行bcrypt加密存储，保证安全
2. 用户登录返回JWT令牌，有效期24小时
3. 文章的创建、更新、删除需要用户认证，且仅作者可操作
4. 评论功能需要用户认证，可对存在的文章发表评论
5. 完善的错误处理，返回对应HTTP状态码和错误信息
6. 日志记录系统运行信息和错误信息，方便调试

## 测试结果
### 注册
![Pasted image 20260103212756](./attachments/Pasted%20image%2020260103212756.png)

### 登录
![Pasted image 20260103213026](./attachments/Pasted%20image%2020260103213026.png)

### 创建博客
![Pasted image 20260103213601](./attachments/Pasted%20image%2020260103213601.png)

### 获取所有文章
![Pasted image 20260103213711](./attachments/Pasted%20image%2020260103213711.png)

### 获取单篇
![Pasted image 20260103213750](./attachments/Pasted%20image%2020260103213750.png)

### 发评论
![Pasted image 20260103214230](./attachments/Pasted%20image%2020260103214230.png)

### 获取评论
![Pasted image 20260103214401](./attachments/Pasted%20image%2020260103214401.png)

### 更新文章
![Pasted image 20260103214626](./attachments/Pasted%20image%2020260103214626.png)

### 删除文章
![Pasted image 20260103214743](./attachments/Pasted%20image%2020260103214743.png)
