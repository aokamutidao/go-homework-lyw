package main

import (
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/dgrijalva/jwt-go"
	"github.com/gin-gonic/gin"
	"github.com/sirupsen/logrus"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

// ====================== 全局变量定义 ======================
var (
	db         *gorm.DB                         // 全局数据库连接
	JwtSecret  = []byte("blog-jwt-secret-2026") // JWT加密密钥，可自定义
	ExpireTime = time.Hour * 24                 // JWT有效期：24小时
	log        = logrus.New()                   // 全局日志对象
)

// ====================== 1. 数据库模型定义（作业要求的3张表，适配PostgreSQL） ======================
// User 用户表: id,username,password,email,创建/更新时间
type User struct {
	gorm.Model
	Username string `gorm:"unique;not null;type:varchar(50)"`  // 唯一、非空
	Password string `gorm:"not null;type:varchar(100)"`        // 加密后的密码，非空
	Email    string `gorm:"unique;not null;type:varchar(100)"` // 唯一、非空
}

// Post 文章表: id,title,content,user_id(关联用户),创建/更新时间
type Post struct {
	gorm.Model
	Title   string `gorm:"not null;type:varchar(100)"` // 文章标题，非空
	Content string `gorm:"not null;type:text"`         // 文章内容，非空
	UserID  uint   `gorm:"not null"`                   // 关联用户ID，外键
	User    User   `gorm:"foreignKey:UserID"`          // GORM关联，一对一
}

// Comment 评论表: id,content,user_id(关联用户),post_id(关联文章),创建时间
type Comment struct {
	gorm.Model
	Content string `gorm:"not null;type:text"` // 评论内容，非空
	UserID  uint   `gorm:"not null"`           // 关联用户ID，外键
	User    User   `gorm:"foreignKey:UserID"`  // GORM关联用户
	PostID  uint   `gorm:"not null"`           // 关联文章ID，外键
	Post    Post   `gorm:"foreignKey:PostID"`  // GORM关联文章
}

// ====================== 2. 初始化数据库连接（PostgreSQL版本，核心修改点） ======================
func initDB() {
	// 配置PostgreSQL连接信息，小白只需要改这里的 密码 即可！！！
	// 格式：postgres://用户名:密码@地址:端口/数据库名?sslmode=disable
	dsn := "postgres://postgres:000000@localhost:5432/blog?sslmode=disable"

	// 连接PostgreSQL数据库
	var err error
	db, err = gorm.Open(postgres.Open(dsn), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Info), // 打印SQL日志，方便调试
	})
	if err != nil {
		log.Fatalf("数据库连接失败: %v", err) // 日志记录错误并退出
	}

	// 自动迁移表结构：没有表就创建，有表就更新字段，不会删数据，作业专用
	err = db.AutoMigrate(&User{}, &Post{}, &Comment{})
	if err != nil {
		log.Fatalf("数据库表迁移失败: %v", err)
	}
	log.Info("PostgreSQL数据库连接成功，表迁移完成！")
}

// ====================== 3. JWT认证核心函数（作业要求：用户登录返回JWT，接口验证JWT） ======================
// JWTClaims JWT的载荷内容，存储用户的核心信息
type JWTClaims struct {
	UserID   uint   `json:"user_id"`
	Username string `json:"username"`
	jwt.StandardClaims
}

// GenerateToken 生成JWT令牌：登录成功后调用
func GenerateToken(userID uint, username string) (string, error) {
	// 设置过期时间
	expire := time.Now().Add(ExpireTime).Unix()
	// 组装载荷
	claims := JWTClaims{
		UserID:   userID,
		Username: username,
		StandardClaims: jwt.StandardClaims{
			ExpiresAt: expire,            // 过期时间
			IssuedAt:  time.Now().Unix(), // 签发时间
			Issuer:    "blog-server",     // 签发者
		},
	}
	// 生成token，使用HS256加密方式
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(JwtSecret)
}

// AuthMiddleware Gin中间件：验证JWT是否有效，作业核心要求！
// 所有需要登录才能访问的接口，都要加这个中间件，比如：创建文章、发表评论、删改文章
func AuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// 1. 从请求头获取token，格式：Bearer xxxxxxxx
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" || len(authHeader) < 7 {
			c.JSON(http.StatusUnauthorized, gin.H{"code": 401, "msg": "未携带token，请先登录"})
			c.Abort() // 终止请求
			return
		}
		tokenString := authHeader[7:] // 截取Bearer后面的token

		// 2. 解析token
		claims := new(JWTClaims)
		token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
			return JwtSecret, nil
		})
		// 3. 验证token有效性
		if err != nil || !token.Valid {
			c.JSON(http.StatusUnauthorized, gin.H{"code": 401, "msg": "token无效或已过期"})
			c.Abort()
			return
		}

		// 4. 验证通过，把用户信息存入上下文，后续接口可以直接获取
		c.Set("userID", claims.UserID)
		c.Set("username", claims.Username)
		c.Next() // 放行请求
	}
}

// ====================== 4. 用户相关接口（注册+登录，作业要求） ======================
// Register 用户注册接口 POST /api/register
func Register(c *gin.Context) {
	var user User
	// 绑定前端传过来的JSON数据到结构体
	if err := c.ShouldBindJSON(&user); err != nil {
		log.Errorf("注册参数错误: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"code": 400, "msg": "参数错误：" + err.Error()})
		return
	}

	// 密码加密：bcrypt加密，作业要求，绝对不能明文存密码
	hashedPwd, err := bcrypt.GenerateFromPassword([]byte(user.Password), bcrypt.DefaultCost)
	if err != nil {
		log.Errorf("密码加密失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"code": 500, "msg": "密码加密失败"})
		return
	}
	user.Password = string(hashedPwd)

	// 写入数据库
	if err := db.Create(&user).Error; err != nil {
		log.Errorf("用户注册失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"code": 500, "msg": "注册失败，用户名/邮箱已存在"})
		return
	}

	// 注册成功
	log.Infof("用户注册成功: %s", user.Username)
	c.JSON(http.StatusOK, gin.H{"code": 200, "msg": "注册成功！"})
}

// Login 用户登录接口 POST /api/login
func Login(c *gin.Context) {
	var req User
	// 绑定参数
	if err := c.ShouldBindJSON(&req); err != nil {
		log.Errorf("登录参数错误: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"code": 400, "msg": "参数错误：" + err.Error()})
		return
	}

	// 根据用户名查询用户
	var user User
	if err := db.Where("username = ?", req.Username).First(&user).Error; err != nil {
		log.Errorf("用户不存在: %s", req.Username)
		c.JSON(http.StatusUnauthorized, gin.H{"code": 401, "msg": "用户名或密码错误"})
		return
	}

	// 验证密码是否正确
	if err := bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(req.Password)); err != nil {
		log.Errorf("用户密码错误: %s", req.Username)
		c.JSON(http.StatusUnauthorized, gin.H{"code": 401, "msg": "用户名或密码错误"})
		return
	}

	// 生成JWT令牌
	token, err := GenerateToken(user.ID, user.Username)
	if err != nil {
		log.Errorf("生成token失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"code": 500, "msg": "登录失败，请重试"})
		return
	}

	// 登录成功，返回token
	log.Infof("用户登录成功: %s", user.Username)
	c.JSON(http.StatusOK, gin.H{
		"code":  200,
		"msg":   "登录成功！",
		"token": token, // 核心返回值，前端后续请求都要带这个token
	})
}

// ====================== 5. 文章相关接口（完整CRUD，作业核心要求） ======================
// CreatePost 创建文章 POST /api/posts  【需要登录+只有作者可操作】
func CreatePost(c *gin.Context) {
	var post Post
	if err := c.ShouldBindJSON(&post); err != nil {
		log.Errorf("创建文章参数错误: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"code": 400, "msg": "参数错误：" + err.Error()})
		return
	}

	// 从上下文获取当前登录的用户ID（AuthMiddleware存入的）
	userID, _ := c.Get("userID")
	post.UserID = userID.(uint) // 给文章绑定作者ID

	// 写入数据库
	if err := db.Create(&post).Error; err != nil {
		log.Errorf("创建文章失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"code": 500, "msg": "创建文章失败"})
		return
	}

	log.Infof("用户ID:%d 创建文章成功，文章标题:%s", post.UserID, post.Title)
	c.JSON(http.StatusOK, gin.H{"code": 200, "msg": "文章创建成功！", "data": post})
}

// GetAllPosts 获取所有文章 GET /api/posts 【无需登录，所有人可看】
func GetAllPosts(c *gin.Context) {
	var posts []Post
	// Preload("User") 关联查询：查询文章的同时，查询文章的作者信息
	if err := db.Preload("User").Find(&posts).Error; err != nil {
		log.Errorf("获取文章列表失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"code": 500, "msg": "获取文章失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"code": 200, "msg": "获取成功", "data": posts})
}

// GetPostById 获取单篇文章详情 GET /api/posts/:id 【无需登录，所有人可看】
func GetPostById(c *gin.Context) {
	// 获取url中的文章ID
	idStr := c.Param("id")
	id, err := strconv.ParseUint(idStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 400, "msg": "文章ID格式错误"})
		return
	}

	var post Post
	// 关联查询作者信息
	if err := db.Preload("User").Where("id = ?", id).First(&post).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"code": 404, "msg": "文章不存在"})
		} else {
			log.Errorf("获取文章详情失败: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"code": 500, "msg": "获取文章失败"})
		}
		return
	}

	c.JSON(http.StatusOK, gin.H{"code": 200, "msg": "获取成功", "data": post})
}

// UpdatePost 更新文章 PUT /api/posts/:id 【需要登录+只有文章作者可修改】
func UpdatePost(c *gin.Context) {
	idStr := c.Param("id")
	id, err := strconv.ParseUint(idStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 400, "msg": "文章ID格式错误"})
		return
	}

	var post Post
	if err := db.Where("id = ?", id).First(&post).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"code": 404, "msg": "文章不存在"})
		return
	}

	// 校验权限：只有文章作者才能修改
	userID, _ := c.Get("userID")
	if post.UserID != userID.(uint) {
		c.JSON(http.StatusForbidden, gin.H{"code": 403, "msg": "无权修改该文章，你不是作者"})
		return
	}

	// 绑定新的文章数据
	var updateData Post
	if err := c.ShouldBindJSON(&updateData); err != nil {
		log.Errorf("更新文章参数错误: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"code": 400, "msg": "参数错误：" + err.Error()})
		return
	}

	// 更新数据库
	db.Model(&post).Updates(updateData)
	log.Infof("用户ID:%d 更新文章成功，文章ID:%d", userID, id)
	c.JSON(http.StatusOK, gin.H{"code": 200, "msg": "文章更新成功！", "data": post})
}

// DeletePost 删除文章 DELETE /api/posts/:id 【需要登录+只有文章作者可删除】
func DeletePost(c *gin.Context) {
	idStr := c.Param("id")
	id, err := strconv.ParseUint(idStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 400, "msg": "文章ID格式错误"})
		return
	}

	var post Post
	if err := db.Where("id = ?", id).First(&post).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"code": 404, "msg": "文章不存在"})
		return
	}

	// 校验权限
	userID, _ := c.Get("userID")
	if post.UserID != userID.(uint) {
		c.JSON(http.StatusForbidden, gin.H{"code": 403, "msg": "无权删除该文章，你不是作者"})
		return
	}

	// 删除文章
	db.Delete(&post)
	log.Infof("用户ID:%d 删除文章成功，文章ID:%d", userID, id)
	c.JSON(http.StatusOK, gin.H{"code": 200, "msg": "文章删除成功！"})
}

// ====================== 6. 评论相关接口（创建+查询，作业要求） ======================
// CreateComment 创建评论 POST /api/comments 【需要登录】
func CreateComment(c *gin.Context) {
	var comment Comment
	if err := c.ShouldBindJSON(&comment); err != nil {
		log.Errorf("创建评论参数错误: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"code": 400, "msg": "参数错误：" + err.Error()})
		return
	}

	// 校验文章是否存在
	var post Post
	if err := db.Where("id = ?", comment.PostID).First(&post).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"code": 404, "msg": "评论的文章不存在"})
		return
	}

	// 绑定当前登录用户ID
	userID, _ := c.Get("userID")
	comment.UserID = userID.(uint)

	// 写入数据库
	if err := db.Create(&comment).Error; err != nil {
		log.Errorf("创建评论失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"code": 500, "msg": "评论失败"})
		return
	}

	log.Infof("用户ID:%d 给文章ID:%d 发表评论成功", comment.UserID, comment.PostID)
	c.JSON(http.StatusOK, gin.H{"code": 200, "msg": "评论成功！", "data": comment})
}

// GetCommentsByPostId 获取某篇文章的所有评论 GET /api/posts/:id/comments 【无需登录】
func GetCommentsByPostId(c *gin.Context) {
	idStr := c.Param("id")
	id, err := strconv.ParseUint(idStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 400, "msg": "文章ID格式错误"})
		return
	}

	var comments []Comment
	// Preload("User") 关联查询评论的作者信息
	if err := db.Preload("User").Where("post_id = ?", id).Find(&comments).Error; err != nil {
		log.Errorf("获取评论失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"code": 500, "msg": "获取评论失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"code": 200, "msg": "获取成功", "data": comments})
}

// ====================== 7. 主函数：初始化+路由配置+启动服务 ======================
func main() {
	// 初始化日志
	log.SetLevel(logrus.InfoLevel)
	log.SetFormatter(&logrus.TextFormatter{TimestampFormat: "2006-01-02 15:04:05"})

	// 初始化数据库
	initDB()

	// 创建Gin引擎，开发模式
	r := gin.Default()

	// ====================== 路由分组 ======================
	// 公开接口：无需登录，所有人可访问
	public := r.Group("/api")
	{
		public.POST("/register", Register)                     // 用户注册
		public.POST("/login", Login)                           // 用户登录
		public.GET("/posts", GetAllPosts)                      // 获取所有文章
		public.GET("/posts/:id", GetPostById)                  // 获取单篇文章
		public.GET("/posts/:id/comments", GetCommentsByPostId) // 获取文章评论
	}

	// 私有接口：需要JWT认证才能访问
	private := r.Group("/api")
	private.Use(AuthMiddleware()) // 全局应用JWT中间件，所有子接口都要验证token
	{
		private.POST("/posts", CreatePost)       // 创建文章
		private.PUT("/posts/:id", UpdatePost)    // 更新文章
		private.DELETE("/posts/:id", DeletePost) // 删除文章
		private.POST("/comments", CreateComment) // 发表评论
	}

	// 启动服务，监听端口8080
	log.Info("博客后端服务启动成功，监听端口: 8080")
	err := r.Run(":8080")
	if err != nil {
		log.Fatalf("服务启动失败: %v", err)
	}
}
