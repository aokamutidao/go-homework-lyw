package main

import (
	"fmt"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

type User struct {
	gorm.Model
	Username     string `gorm:"uniqueIndex;not null"`
	Email        string `gorm:"uniqueIndex;not null"`
	PasswordHash string `gorm:"not null"`
	Posts        []Post `gorm:"foreignKey:UserID"`
	PostCount    int64  `gorm:"not null;default:0"` // 用于存储文章数量
}

type Post struct {
	gorm.Model
	Title          string    `gorm:"not null"`
	Content        string    `gorm:"type:text;not null"`
	UserID         uint      `gorm:"not null;index"`
	User           User      `gorm:"references:ID"`
	Comments       []Comment `gorm:"foreignKey:PostId"`
	CommentsStatus string    `gorm:"type:varchar(20);default:'有评论'"` // 用于标记是否有评论
}

func (p *Post) AfterCreate(tx *gorm.DB) error {
	if err := tx.Model(&User{}).Where("id = ?", p.UserID).Update("post_count", gorm.Expr("post_count + ?", 1)).Error; err != nil {
		fmt.Println("更新用户文章数量失败：", err)
		return err
	}
	fmt.Println("用户文章数量更新成功")
	return nil
}

type Comment struct {
	gorm.Model
	Content    string `gorm:"type:text; not null"`
	PostId     uint   `gorm:"not null;index"`
	Post       Post   `gorm:"references:ID"`
	AuthorName string `gorm:"not null"`
}

func (c *Comment) AfterDelete(tx *gorm.DB) error {
	var commentCount int64
	if err := tx.Model(&Comment{}).Where("post_id = ? AND deleted_at IS NULL", c.PostId).Count(&commentCount).Error; err != nil {
		fmt.Println("计算文章评论数量失败：", err)
		return err
	}
	if commentCount == 0 {
		if err := tx.Model(&Post{}).Where("id = ?", c.PostId).Update("CommentsStatus", "无评论").Error; err != nil {
			fmt.Println("更新文章评论状态失败：", err)
			return err
		}
		fmt.Println("文章评论状态更新为无评论")
	} else {
		fmt.Println("文章仍有评论，无需更新评论状态")
	}
	return nil
}

func insertTestData(db *gorm.DB) (User, Post, Post, []Comment) {
	// 先清空原有测试数据（避免重复插入）
	db.Unscoped().Where("1=1").Delete(&Comment{})
	db.Unscoped().Where("1=1").Delete(&Post{})
	db.Unscoped().Where("1=1").Delete(&User{})

	// 插入用户
	user := User{
		Username:     "test_user",
		Email:        "test@example.com",
		PasswordHash: "hash123456",
	}
	db.Create(&user)

	// 插入2篇文章
	post1 := Post{
		Title:   "第一篇文章",
		Content: "这是我的第一篇博客文章",
		UserID:  user.ID,
	}
	db.Create(&post1)
	post2 := Post{
		Title:   "第二篇文章",
		Content: "这是我的第二篇博客文章",
		UserID:  user.ID,
	}
	db.Create(&post2)

	// 给第一篇文章插入3条评论，第二篇插入1条评论（确保第一篇是评论最多的）
	comment1 := Comment{Content: "第一篇评论", PostId: post1.ID, AuthorName: "评论者1"}
	db.Create(&comment1)
	comment2 := Comment{Content: "第二篇评论", PostId: post1.ID, AuthorName: "评论者2"}
	db.Create(&comment2)
	comment3 := Comment{Content: "第三篇评论", PostId: post1.ID, AuthorName: "评论者3"}
	db.Create(&comment3)
	comment4 := Comment{Content: "只有这一条评论", PostId: post2.ID, AuthorName: "评论者4"}
	db.Create(&comment4)
	comments := []Comment{comment1, comment2, comment3, comment4}
	fmt.Println("测试数据插入成功！")
	return user, post1, post2, comments
}

func main() {
	db, err := gorm.Open(sqlite.Open("blogsystem.db"), &gorm.Config{})
	if err != nil {
		panic("failed to connect database" + err.Error())
	}

	// Migrate the schema
	if err := db.AutoMigrate(&User{}, &Post{}, &Comment{}); err != nil {
		panic("failed to migrate database schema" + err.Error())
	}
	println("Database migrated successfully")

	user, _, post2, comments := insertTestData(db)
	fmt.Println("===== 功能1：查询插入的用户及其所有文章+评论 =====")
	var targetUser User
	if err := db.Preload("Posts.Comments").First(&targetUser, user.ID).Error; err != nil {
		fmt.Println("查询用户失败：", err)
	} else {
		fmt.Printf("用户信息：ID=%d, 用户名=%s, 邮箱=%s\n", targetUser.ID, targetUser.Username, targetUser.Email)
		for _, post := range targetUser.Posts {
			fmt.Printf("  文章ID=%d, 标题=%s, 内容=%s\n", post.ID, post.Title, post.Content)
			for _, comment := range post.Comments {
				fmt.Printf("    评论ID=%d, 作者=%s, 内容=%s\n", comment.ID, comment.AuthorName, comment.Content)
			}
		}
	}
	fmt.Println("\n===== 功能2：查询评论数量最多的文章 =====")
	var mostCommentedPost Post
	subQuery := db.Model(&Comment{}).Select("post_id, COUNT(*) as comment_count").Group("post_id")
	err = db.Joins("LEFT JOIN (?) c ON posts.id = c.post_id", subQuery).Order("c.comment_count DESC").First(&mostCommentedPost).Error
	if err != nil {
		fmt.Println("查询评论数量最多的文章失败：", err)
	} else {
		var commentCount int64
		db.Model(&Comment{}).Where("post_id = ?", mostCommentedPost.ID).Count(&commentCount)
		fmt.Printf("评论数量最多的文章：ID=%d, 标题=%s, 评论数量=%d\n", mostCommentedPost.ID, mostCommentedPost.Title, commentCount)
	}

	// 验证1：查询用户，查看文章数量是否更新为2
	fmt.Println("\n===== 验证1：查询用户文章数量 =====")
	if err := db.Where("username = ?", "test_user").First(&targetUser).Error; err != nil {
		fmt.Println("查询用户失败：", err)
	} else {
		fmt.Printf("用户信息：ID=%d, 用户名=%s, 文章数量=%d\n", targetUser.ID, targetUser.Username, targetUser.PostCount)
	}

	// 验证2：删除第二篇文章的唯一评论，验证 Comment 的 AfterDelete 钩子
	fmt.Println("\n===== 验证2：删除评论并检查文章状态 =====")
	var targetComment Comment = comments[3]
	if err := db.Delete(&targetComment).Error; err != nil {
		fmt.Println("删除评论失败：", err)
	}

	// 验证3：查询第二篇文章，查看评论状态是否更新为"无评论"
	fmt.Println("\n===== 验证3：查询文章评论状态 =====")
	var targetPost Post
	if err := db.First(&targetPost, post2.ID).Error; err != nil {
		fmt.Println("查询文章失败：", err)
	} else {
		fmt.Printf("文章信息：ID=%d, 标题=%s, 评论状态=%s\n", targetPost.ID, targetPost.Title, targetPost.CommentsStatus)
	}
}
